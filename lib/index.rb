class Index

  DATA_PATH = "#{File.dirname(__FILE__)}/../data/"
  DOC_PATH = "#{File.dirname(__FILE__)}/../docs/"
  FILE_NAMES = {
    index: "index.txt", 
    relevant: "relevant_nofback.txt",
    lengths: "doc_lengths.txt",
    feedback: "feedback.txt"
  }
  QUERIES = [
    "financial instruments being traded on the American stock exchange",
    "stocks shares stock market exchange New York traded trading"
  ]

  attr_accessor :terms, :lengths, :n, :relevant, :feedback

  # term  document_frequency  {doc  term_frequency}*
  def initialize
    self.terms = Hash.new { |h, k| h[k] = {frequency: 0.0, documents: Hash.new { |h, k| h[k] = 0 } } }
    self.lengths = {}
    self.relevant = []
    self.feedback = []

    feedback = DATA_PATH + FILE_NAMES[:feedback]
    File.open(feedback, "r").each_line do |line|
      document, feedback = self.parse_feedback line
      self.feedback << [document, feedback] 
    end

    index = DATA_PATH + FILE_NAMES[:index]
    File.open(index, "r").each_line do |line|
      term, documents = self.parse_term line
      documents.each do |document, frequency|
        self.terms[term][:documents][document] += frequency 
      end
      self.terms[term][:frequency] = self.terms[term][:documents].length
    end

    self.n = self.terms.map{|k,v| v[:frequency]}.inject{|a,b| a+b}

    lengths = DATA_PATH + FILE_NAMES[:lengths]
    File.open(lengths, "r").each_line do |line|
      document, length = self.parse_length line
      self.lengths[document] = length
    end

    relevant = DATA_PATH + FILE_NAMES[:relevant]
    File.open(relevant, "r").each_line do |line|
      self.relevant << line.strip
    end

  end

  def parse_term line
    parts = line.split(" ")
    term = parts[0].downcase
    documents = {}
    parts.drop(2).each_slice(2) do |document, term_frequency|
      documents[document] = term_frequency.to_f
    end
    return term, documents
  end

  def parse_length line
    parts = line.split(" ")
    return parts[0], parts[1].to_f
  end

  def parse_feedback line
    parts = line.split(" ")
    return parts[0], parts[1].to_i==1
  end

  def query q, limit=nil, feedback=true
    q = self.rocchio(q)

    results = Hash.new { |h, k| h[k] = 0 }

    q.each do |term, weight|
      document_frequency = self.terms[term][:frequency]
      if document_frequency > 0 
        documents = self.terms[term][:documents]
        documents.each do |document, frequency|
          results[document] += frequency/document_frequency * weight
        end
      end
    end

    # results.each{|document, result| results[document] = result/self.lengths[document]}

    results = results.sort{|a,b| b[1] <=> a[1]}
    results = results.first(limit) if limit
    return results
  end

  def rocchio query
    alpha = 1
    beta = 0.75
    gamma = -0.25
    
    query.split(" ").map do |term| 
      term = term.downcase
      weight = alpha * 1

      document_frequency = self.terms[term][:frequency]
      if document_frequency > 0 
        self.feedback.each do |document, feedback|
          frequency = self.terms[term][:documents][document]
          adjust = frequency/document_frequency # have not further divided by document length, i.e. just d, not d/|d|
          weight += (feedback ? beta : gamma) * adjust
        end
      end

      weight = 0 if weight < 0

      [term, weight]
    end
  end

  def precision_at_recall q=QUERIES[0]
    results = self.query q, 500
    results = results.map{|r| r[0]} - self.feedback.map{|f| f[0]}

    positions = self.relevant.map{|document| results.index(document)}.sort

    eval = {average: 0, results: []}

    for i in [0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]
      n = (i * self.relevant.length).round
      retrieved = results[0..positions[n-1]]
      correct = retrieved & self.relevant
      precision = correct.length.to_f/retrieved.length.to_f
      recall = correct.length.to_f/self.relevant.length.to_f
      eval[:results] << {precision: precision, recall: recall}  
    end
    
    eval[:average] = eval[:results].map{|h| h[:precision]}.inject{|a,b| a+b}
    eval[:average] = eval[:average] / eval[:results].length

    return eval
  end

end


# EVALUATION
# 
# "financial instruments being traded on the American stock exchange" => 
#   {:average=>0.15512524462717786, 
#    :results=>[
#      {:precision=>0.15789473684210525, :recall=>0.09375}, 
#      {:precision=>0.2, :recall=>0.1875}, 
#      {:precision=>0.2631578947368421, :recall=>0.3125}, 
#      {:precision=>0.24074074074074073, :recall=>0.40625}, 
#      {:precision=>0.15841584158415842, :recall=>0.5}, 
#      {:precision=>0.14393939393939395, :recall=>0.59375}, 
#      {:precision=>0.1286549707602339, :recall=>0.6875}, 
#      {:precision=>0.08695652173913043, :recall=>0.8125}, 
#      {:precision=>0.0830945558739255, :recall=>0.90625}, 
#      {:precision=>0.08839779005524862, :recall=>1.0}
#    ]}
# 
# "stocks shares stock market exchange New York traded trading" =>
#   {:average=>0.6774003935705063, 
#    :results=>[
#      {:precision=>1.0, :recall=>0.09375}, 
#      {:precision=>0.8571428571428571, :recall=>0.1875}, 
#      {:precision=>0.9090909090909091, :recall=>0.3125}, 
#      {:precision=>0.9285714285714286, :recall=>0.40625}, 
#      {:precision=>0.8, :recall=>0.5}, 
#      {:precision=>0.59375, :recall=>0.59375}, 
#      {:precision=>0.5, :recall=>0.6875}, 
#      {:precision=>0.45614035087719296, :recall=>0.8125}, 
#      {:precision=>0.4027777777777778, :recall=>0.90625}, 
#      {:precision=>0.32653061224489793, :recall=>1.0}
#    ]}
# 
# 
# 