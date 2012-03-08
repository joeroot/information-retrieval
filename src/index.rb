require 'stemmer'

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

  def initialize
    # Terms are stored in a Hash, with each term hash containing a frequency 
    # score and a documents hash. The documents hash is structured such that 
    # each document maps to the term's frequency within the document.
    self.terms = Hash.new { |h, k| h[k] = {
      frequency: 0.0, 
      documents: Hash.new { |h, k| h[k] = 0 } 
    } }

    # Lengths are stored in a Hash, mapping each document to it's length.
    self.lengths = {}

    # Relevant documents for evaluation are stored within an array, for 
    # comparison with query results.
    self.relevant = []

    # Feedback is stored as an array of arrays, with each child array containing
    # a document string in index zero and the feedback type (relevant or not?) 
    # in index one.
    self.feedback = []

    # Reads and parses the index file.
    index = DATA_PATH + FILE_NAMES[:index]
    File.open(index, "r").each_line do |line|
      term, documents = self.parse_term line
      documents.each do |document, frequency|
        self.terms[term][:documents][document] += frequency 
      end
      self.terms[term][:frequency] = self.terms[term][:documents].length
    end

    self.n = self.terms.map{|k,v| v[:frequency]}.inject{|a,b| a+b}

    # Reads and parses the length file.
    lengths = DATA_PATH + FILE_NAMES[:lengths]
    File.open(lengths, "r").each_line do |line|
      document, length = self.parse_length line
      self.lengths[document] = length
    end

    # Reads and parses the relevant file.
    relevant = DATA_PATH + FILE_NAMES[:relevant]
    File.open(relevant, "r").each_line do |line|
      self.relevant << line.strip
    end

    # Reads and parses the feedback file.
    feedback = DATA_PATH + FILE_NAMES[:feedback]
    File.open(feedback, "r").each_line do |line|
      document, feedback, terms = self.parse_feedback line
      self.feedback << [document, feedback, terms] 
    end

  end

  # Given a line from the index file, this function parses and returns the term 
  # information stored within it. The term and its document frequency are 
  # extracted, and the term itself is downcased. After this we iterate over the
  # remaning document and term frequency pairs. Finally, we return the term and 
  # an array of documents with term frequency.
  def parse_term line
    parts = line.split(" ")
    term = parts[0].downcase
    documents = {}
    parts.drop(2).each_slice(2) do |document, term_frequency|
      documents[document] = term_frequency.to_f
    end
    return term, documents
  end

  # Given a line from the lengths file, this function parses and returns the 
  # document name and length.
  def parse_length line
    parts = line.split(" ")
    return parts[0], parts[1].to_f
  end

  # Given a line from the feedback file, this function parses and returns the 
  # document name and a boolean value denoting whether the document's feedback 
  # is marked as relevant or not.
  def parse_feedback line
    parts = line.split(" ")
    document = parts[0]
    feedback = parts[1].to_i==1
    terms = self.terms.map{|term, values| (values[:documents].keys.include? document) ? term : nil}.compact
    return document, feedback, terms
  end

  # Query function takes a query, a limit on the number of results to be 
  # returned, and a boolean denooting whether it should take feedback into 
  # account.
  def query q, limit=nil, feedback=true
    # The query is tokenised and weighted according to the 2hio algorithm
    q = self.rocchio(q)
    puts q.length

    # A results array is initialised, in which each document maps to its results
    # weight
    results = Hash.new { |h, k| h[k] = 0 }

    # For each query term (and adjusted feedback weight), we iterate over all
    # documents containing the term and for each document, add it to the results
    # if it does not exist, and then updated its score with the TF-IDF and term
    # weight accordingly.
    q.each do |term, weight|
      document_frequency = self.terms[term][:frequency]
      if document_frequency > 0 
        documents = self.terms[term][:documents]
        documents.each do |document, frequency|
          results[document] += frequency/document_frequency * weight
        end
      end
    end

    # Each document's score is normalised according to it's length
    results.each do |document, result| 
      results[document] = result/self.lengths[document]
    end

    # The results are sorted according to most relevant first. If a limit has 
    # been requested this is then enforced, before finally returning the
    # results.
    results = results.sort{|a,b| b[1] <=> a[1]}
    results = results.first(limit) if limit
    return results
  end

  # Given a query, this function tokenises it, before applying the Rocchio 
  # algorithm to generate a set of weights for each term based upon feedback.
  def rocchio query
    alpha = 0
    beta = 0.75
    gamma = -0.25
    
    query = query.downcase.split(" ")
    init = query

    # We append each positive feedback document's terms to our new query vector. 
    self.feedback.each { |document, feedback, terms| query |= terms if feedback }

    query.map do |term| 
      # If the term was in the original query, we set its vector wight to 1, 
      # otherwise its set to 0.
      weight = (init.include? term) ? 1 : 0
      weight += alpha

      document_frequency = self.terms[term][:frequency]
      if document_frequency > 0 
        self.feedback.each do |document, feedback, terms|
          frequency = self.terms[term][:documents][document]
          adjust = frequency/document_frequency
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

    # Given our array of relevant documents (parsed in the initialisation), we
    # determine each of the relevant document's position within the query 
    # results array. 
    positions = self.relevant.map{|document| results.index(document)}.sort

    # Our evaluation results are stored in a hash containing the average
    # precision at recall, along with each of the recall/precision pairs used
    # to construct that average.
    eval = {average: 0, results: []}

    # Given an array of recalls, the algorithm will try and match this recall
    # as best as possible. For each recall, we calculate the number of relevant
    # documents which would have to be found, n. Once n has been calculated,
    # we create a retrieved array, containing all results up to and including
    # the said relevant document. The precision and recall values are then 
    # calculated accordingly, and added to the results.
    for i in [0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]
      n = (i * self.relevant.length).round
      retrieved = results[0..positions[n-1]]
      correct = retrieved & self.relevant
      precision = correct.length.to_f/retrieved.length.to_f
      recall = correct.length.to_f/self.relevant.length.to_f
      eval[:results] << {precision: precision, recall: recall}  
    end
    
    # An average precision at recall is calculated.
    eval[:average] = eval[:results].map{|h| h[:precision]}.inject{|a,b| a+b}
    eval[:average] = eval[:average] / eval[:results].length

    return eval
  end

end