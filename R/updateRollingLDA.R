#' @title Updating an existing RollingLDA object
#'
#' @description
#' Performs an update of an existing object consisting of a rolling version
#' of Latent Dirichlet Allocation.
#'
#' @details The function uses an existing \code{\link{RollingLDA}} object and
#' models new texts with a specified memory as initialization of the new LDA chunk.
#'
#' The function returns a \code{\link{RollingLDA}} object. You can receive results and
#' all other elements of this object with getter functions (see \code{\link{getChunks}}).
#'
#' @family RollingLDA functions
#'
#' @param x [\code{named list}]\cr
#' \code{\link{RollingLDA}} object.
#' @param texts [\code{named list}]\cr
#' Tokenized texts.
#' @param dates [\code{(un)named Date}]\cr
#' Sorted dates of the tokenized texts. If unnamed, it must match the order of texts.
#' @param chunks [\code{Date} or \code{character(1)}]\cr
#' Sorted dates of the beginnings of each chunk to be modeled as updates.
#' If passed as \code{character}, dates are determined by passing the minimum of
#' \code{dates} as \code{from} argument, \code{max(dates)} as \code{to} argument
#' and \code{chunks} as \code{by} argument in \code{\link{seq.Date}}.
#' If not passed, all texts are interpreted as one chunk.
#' @param memory [\code{Date}, \code{character(1)} or \code{integer(1)}]\cr
#' Dates of the beginnings of each chunk's memory. If passed as \code{character},
#' dates are determined by using the dates of the beginnings of each chunk and
#' substracting the given time interval in \code{memory} passing it as
#' \code{by} argument in \code{\link{seq.Date}}. If passed as
#' \code{integer/numeric}, the dates are determined by going backwards the
#' modeled texts chronologically and taking the date of the text at position
#' \code{memory}.
#' @param param [\code{named list}] with entries (Default is \code{getParam(x)})
#'  \describe{
#'   \item{\code{vocab.abs}}{[\code{integer(1)}]
#'   An absolute lower bound limit for which words are taken into account. All
#'   words are considered in the vocabularies that have a count higher than
#'   \code{vocab.abs} over all texts and at the same time a higher relative
#'   frequency than \code{vocab.rel}.}
#'   \item{\code{vocab.rel}}{[0,1]
#'   A relative lower bound limit for which words are taken into account.
#'   See also \code{vocab.abs}.}
#'   \item{\code{vocab.fallback}}{[\code{integer(1)}]
#'   An absolute lower bound limit for which words are taken into account. All
#'   words are considered in the vocabularies that have a count higher than
#'   \code{vocab.fallback} over all texts even if they might not have a higher
#'   relative frequency than \code{vocab.rel}.}
#'   \item{\code{doc.abs}}{[\code{integer(1)}]
#'   An absolute lower bound limit for which texts are taken into account. All
#'   texts are considered for modeling that have more words (subsetted to words
#'   occurring in the vocabularies) than \code{doc.abs}.}
#' }
#' @param compute.topics [\code{logical(1)}]\cr
#' Should the topic matrix of the LDA model be computed? Default is \code{TRUE}.
#' @param memory.fallback [\code{integer(1)}]\cr
#' If there are no texts as memory in a certain chunk, \code{memory} is
#' determined by going backwards the modeled texts chronologically and taking
#' the date of the text at position \code{memory.fallback}.
#' Default is 0, which means "end the fitting".
#' @param ... not implemented
#' @return [\code{named list}] with entries
#'  \describe{
#'   \item{\code{id}}{[\code{character(1)}] See above.}
#'   \item{\code{lda}}{\code{\link{LDA}} object of the fitted RollingLDA.}
#'   \item{\code{docs}}{[\code{named list}] with modeled texts in a preprocessed format.
#'   See \code{\link[tosca]{LDAprep}}}
#'   \item{\code{dates}}{[\code{named Date}] with dates of the modeled texts.}
#'   \item{\code{vocab}}{[\code{character}] with the vocabularies considered
#'   for modeling.}
#'   \item{\code{chunks}}{[\code{data.table}] with specifications for each
#'   model chunk.}
#'   \item{\code{param}}{[\code{named list}] with parameter specifications for
#'   \code{vocab.abs} [\code{integer(1)}], \code{vocab.rel} [0,1],
#'   \code{vocab.fallback} [\code{integer(1)}] and
#'   \code{doc.abs} [\code{integer(1)}]. See above for explanation.}
#' }
#'
#' @examples
#' \donttest{
#' roll_lda = RollingLDA(texts = economy_texts[economy_dates < "2008-05-01"],
#'                       dates = economy_dates[economy_dates < "2008-05-01"],
#'                       chunks = "month",
#'                       memory = "month",
#'                       init = 100,
#'                       K = 10,
#'                       type = "lda")
#'
#' # updateRollingLDA = RollingLDA, if first argument is a RollingLDA object
#' roll_update = RollingLDA(roll_lda,
#'                          texts = economy_texts[economy_dates >= "2008-05-01"],
#'                          dates = economy_dates[economy_dates >= "2008-05-01"],
#'                          chunks = "month",
#'                          memory = "month")
#'
#' roll_update
#' getChunks(roll_update)
#' }
#'
#' @export updateRollingLDA
updateRollingLDA = function(x, texts, dates, chunks, memory, param = getParam(x),
                            compute.topics = TRUE, memory.fallback = 0L, ...){

  if (!is.RollingLDA(x)){
    is.RollingLDA(x, verbose = TRUE)
    stop("\"x\" is not a RollingLDA object")
  }

  if (is.null(names(dates))) names(dates) = names(texts)
  dates = dates[match(names(dates), names(texts))]
  assert_date(try(as.Date(dates)), any.missing = FALSE, len = length(texts),
              lower = max(getDates(x))+1)
  dates = as.Date(dates)

  if (missing(chunks)) chunks = min(dates)
  if (!is.Date(chunks)){
    chunks.try = try(as.Date(chunks), silent = TRUE)
    if (inherits(chunks.try, "try-error")){
      chunks = seq.Date(from = min(dates), to = max(dates), by = tolower(chunks))
    }
    else chunks = chunks.try
  }
  assert_date(chunks, any.missing = FALSE, lower = max(getDates(x))+1)
  assert_date(min(dates), any.missing = FALSE, lower = min(chunks))

  if (!is.Date(memory)){
    if (is.numeric(memory)){
      tmp = sort(c(getDates(x), dates), decreasing = TRUE)
      memory = as.Date(unname(
        sapply(chunks, function(x) (as.character(tmp[tmp < x])[memory]))))
    }
    memory.try = try(as.Date(memory), silent = TRUE)
    if (inherits(memory.try, "try-error")){
      if (!grepl("[0-9]", memory)) memory = paste0("1 ", memory)
      memory = as.Date(sapply(chunks, function(x)
        as.character(seq.Date(from = x, by = paste0("-", tolower(memory)), length.out = 2)[2])))
    }
    else memory = memory.try
  }
  assert_date(memory, any.missing = FALSE, len = length(chunks))
  if (any(memory > chunks)){
    tmp = memory > chunks
    stop("all dates in \"memory\" must not be greater than the pendant in \"chunks\", but ",
         paste0(memory[tmp], " > " , chunks[tmp], collapse = ", "))
  }
  if (is.unsorted(chunks)) stop("\"chunks\" must be sorted")
  if (is.unsorted(memory)) stop("\"memory\" must be sorted")
  if (length(chunks) == 1){
    return(updateRollingLDA_one_step(
      x = x,
      texts = texts,
      dates = dates,
      memory = memory,
      param = param,
      compute.topics = compute.topics,
      memory.fallback = memory.fallback
    ))
  }else{
    chunks = c(chunks[-1], max(dates)+1)
    res = x
    for (i in seq_along(chunks)){
      message("Fitting Chunk ", i, "/", length(chunks), ".")
      res = updateRollingLDA_one_step(
        x = res,
        texts = texts[dates < chunks[i]],
        dates = dates[dates < chunks[i]],
        memory = memory[i],
        compute.topics = FALSE,
        memory.fallback = memory.fallback
      )
      texts = texts[dates >= chunks[i]]
      dates = dates[dates >= chunks[i]]
    }
    if (compute.topics){
      message("Compute topic matrix.")
      res$lda$topics = compute_topics_matrix_from_assignments(
        assignments = getAssignments(getLDA(res)),
        docs = getDocs(res),
        K = getK(getLDA(res)),
        vocab = getVocab(res))
    }
    invisible(res)
  }
}

updateRollingLDA_one_step = function(x, texts, dates, memory, param = getParam(x),
                                     compute.topics = TRUE, memory.fallback = 0L){

  if (!is.RollingLDA(x)){
    is.RollingLDA(x, verbose = TRUE)
    stop("\"x\" is not a RollingLDA object")
  }

  vocab.abs = param$vocab.abs
  vocab.rel = param$vocab.rel
  vocab.fallback = param$vocab.fallback
  doc.abs = param$doc.abs
  assert_int(vocab.abs, lower = 0)
  assert_int(vocab.rel, lower = 0, upper = 1)
  assert_int(vocab.fallback, lower = 0)
  assert_int(doc.abs, lower = 0)
  assert_int(memory.fallback, lower = 0)
  assert_list(texts, types = "character", names = "unique")
  assert_date(memory, any.missing = FALSE, len = 1)
  assert_date(dates, any.missing = FALSE, len = length(texts), lower = memory)

  if (length(dates) == 0){
    message("there are no texts in this chunk - skip chunk")
    warning("there are no texts in this chunk - skip chunk")
    return(invisible(x))
  }

  dates.memory = getDates(x)
  assert_date(dates, lower = max(dates.memory)+1)

  if (!any(dates.memory >= memory)){
    if (memory.fallback > 0){
      memory = sort(dates.memory, decreasing = TRUE)[memory.fallback]
      warning("there are no texts as memory for this chunk - ",
                  "using \"memory.fallback\" = ", memory.fallback,
                  " to determine memory: ", memory)
      message("there are no texts as memory for this chunk - ",
                  "using \"memory.fallback\" = ", memory.fallback,
                  " to determine memory: ", memory)
    }else{
      warning("there are no texts as memory for this chunk - skip chunk")
      message("there are no texts as memory for this chunk - skip chunk")
      return(invisible(x))
    }
  }

  id.memory = names(dates.memory[dates.memory >= memory])
  docs.memory = getDocs(x, names = id.memory)
  n.memory = length(docs.memory)

  step.new = rollinglda_one_step(
    lda = getLDA(x),
    docs = docs.memory,
    texts = texts,
    vocab = getVocab(x),
    vocab.abs = vocab.abs,
    vocab.rel = vocab.rel,
    vocab.fallback = vocab.fallback,
    doc.abs = doc.abs
  )
  chunks = merge.data.table(getChunks(x), data.table(
    chunk.id = max(getChunks(x)$chunk.id) + 1L,
    start.date = min(dates),
    end.date = max(dates),
    memory = memory,
    n = step.new$n.docs.new,
    n.discarded = step.new$n.docs.deleted,
    n.memory = n.memory,
    n.vocab = length(step.new$vocab)
  ), all = TRUE)
  dates = dates[na.omit(match(names(step.new$docs), names(dates)))]
  dates = c(getDates(x), dates)
  docs = append(getDocs(x, names = id.memory, inverse = TRUE), step.new$docs)
  res = list(id = getID(x), lda = step.new$lda,
             docs = docs, dates = dates, vocab = step.new$vocab, chunks = chunks,
             param = list(vocab.abs = vocab.abs, vocab.rel = vocab.rel,
                          vocab.fallback = vocab.fallback, doc.abs = doc.abs))
  class(res) = "RollingLDA"
  if (compute.topics){
    message("Compute topic matrix.")
    res$lda$topics = compute_topics_matrix_from_assignments(
      assignments = getAssignments(getLDA(res)),
      docs = getDocs(res),
      K = getK(getLDA(res)),
      vocab = getVocab(res))
  }
  invisible(res)
}

#' @rdname updateRollingLDA
#' @export
RollingLDA.RollingLDA = updateRollingLDA
