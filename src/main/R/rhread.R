#' Read Key/Value Pairs From The HDFS
#'
#' Reads all or a limited number of key/value pairs from HDFS files.
#' 
#' @param files Path to file or directory containing map, sequence, or
#'   text file to be read on the HDFS. This can also be the output from rhwatch(provided read=FALSE) or rhmr.
#' @param type Type of file on HDFS.  Must be 'sequence', 'map', or 'text'.
#' @param max Maximum number of key/value pairs to read for map and sequence
#'   files.  Maximum number of lines to read for text files.
#' @param mc Set to lapply by default. User can change this to \code{mclapply} for parallel lapply.
#' @param textual if the keys and values are hadoop Text objects
#' @param skip Files to skip while reading the hdfs.  Various installs of Hadoop add additional log
#' info to HDFS output from MapReduce.  Attempting to read these files is not what we want to do 
#' in rhread.  To get around this we specify pieces of filenames to grep and remove from the read.
#'          skip is a vector argument just to have sensible defaults for a number of different systems.
#'          You can learn which if any files need to be skipped by using rhls on target directory.
#' @param verbose logical - print messages about what is being done
#' @param ... arguments passed to the function
#' @return For map and sequence files, a list of key, pairs of up to length
#'   MAX.  For text files, a matrix of lines, each row a line from the text
#'   files.
#' @details Reads the key,value pairs from the files pointed to by \code{files}. The
#' source \code{files} can end in a wildcard (*) e.g. \emph{/path/input/p*}
#' will read all the key,value pairs contained in files starting with \emph{p}
#' in the folder \emph{/path/input/}.
#' 
#' The parameter \code{type} specifies the format of \code{files}. This can be
#' one of \code{text}, \code{map} or \code{sequence} which imply a Text file,
#' MapFile or a SequenceFile respectively.
#' 
#' The parameter \code{max} specifies the maximum number of entries to read, by
#' default all the key,value pairs will be read.  Specifying \code{max} for
#' text files, limits the number of lines read.
#' 
#' \code{mc} is by default \code{lapply}. The user can change this to mclapply for faster throughput.
#' 
#' Data written by \code{\link{rhwrite}} can be read using \code{rhread}.
#' @author Saptarshi Guha
#' @seealso \code{\link{rhget}}, \code{\link{rhput}},
#'   \code{\link{rhdel}}, \code{\link{rhwrite}}, \code{\link{rhsave}}
#' @keywords read HDFS file
#' @export
rhread <- function(files, 
   type = c("sequence"), 
   max = -1L, 
   skip = rhoptions()$file.types.remove.regex, 
   mc = lapply, 
   textual = FALSE, 
   verbose = TRUE,
   ...
) {
   if (is(files, "rhwatch")) 
      files <- rhofolder(files)
   files <- rhabsolute.hdfs.path(files)
   # if type is map, weed out index files in the part-r- directories
   files <- getypes(files, type, skip)
   max <- as.integer(max)
   switch(type, gzip = {
      stop("GZIP not supported")
   }, text = {
      rhread.text(files, max = max)
   }, map = {
      rhread.sequence(files, max = max, mc = mc, textual = textual, 
         verbose = verbose)
   }, sequence = {
      rhread.sequence(files, max = max, mc = mc, textual = textual, 
         verbose = verbose)
   })
}

rhread.text <- function(files, max) {
   x <- c()
   i <- 1
   ntoread <- if (max > 0) 
      as.integer(max) else Inf
   while (ntoread > 0 && i <= length(files)) {
      a <- hdfsReadLines(files[i], if (ntoread == Inf) 
         -1L else ntoread)
      ntoread <- ntoread - length(a)
      x <- c(x, a)
      i <- i + 1
   }
   return(x)
}

rhread.sequence <- function(files, max, mc, textual = FALSE, verbose = FALSE) {
   a1 <- proc.time()["elapsed"]
   handle <- .jnew("org/godhuli/rhipe/SequenceFileIterator")
   j <- list()
   a <- handle$init(files, as.integer(10 * 1024 * 1024), as.integer(max), rhoptions()$server)
   handle$setTextual(as.logical(textual))
   bread <- 0
   while (handle$hasMoreElements()) {
      v <- handle$nextChunk()
      j[[length(j) + 1]] <- mc(rhuz(v), function(r) list(rhuz(r[[1]]), rhuz(r[[2]])))
      bread <- bread + length(v)
   }
   v <- unlist(j, recursive = FALSE)
   a2 <- proc.time()["elapsed"]
   if(verbose)
      message(makeMessage(bread, length(v), a2 - a1))
   v
}


makeMessage <- function(b, l, d) {
   units <- "KB"
   if (b < 1024 * 1024) 
      b <- b/1024 else if (b < 1024 * 1024 * 1024) {
      units <- "MB"
      b <- b/(1024 * 1024)
   } else {
      units <- "GB"
      b <- b/(1024 * 1024 * 1024)
   }
   if (d < 60) {
      tt <- d
      tu <- "seconds"
   } else {
      tt <- d/60
      tu <- "minutes"
   }
   sprintf("Read %s objects(%s %s) in %s %s", l, round(b, 2), units, round(tt, 2), 
      tu)
}

#' Iterates Through the Records of Sequence Files
#'
#' Can be used to iterate through the records of a Sequence File(or collection thereof)
#' 
#' @param files Path to file or directory containing  sequence files.  This can also be the output from rhwatch(provided read=FALSE) or rhmr.
#' @param type Is it 'sequence' or 'map'. Ideally should be auto-determined.
#' @param chunksize Number of records or bytes to read. Depends on 'chunk'
#' @param chunk either "records" or "bytes"
#' @param skip Files to skip while reading the hdfs.  Various installs of Hadoop add additional log
#' info to HDFS output from MapReduce.  Attempting to read these files is not what we want to do.
#' To get around this we specify pieces of filenames to grep and remove from the read.  \code{skip} is a vector argument just to have sensible defaults for a number of different systems.  You can learn which if any files need to be skipped by using rhls on the target directory.
#' @param mc Set to lapply by default. User can change this to \code{mclapply} for parallel lapply
#' @param textual if the keys and values are hadoop Text objects
#' @examples
#' 
#' \dontrun{
#'    j <- rhwatch(map = rhmap(rhcollect(r,k)), reduce=0, input=c(36,3), read=FALSE)
#'    a <- rhIterator(j, chunksize=11)
#'    while (length(b <- a()) > 0) doSomethingWith(b)
#' }
#' @export
rhIterator <- function(files, type = "sequence", chunksize = 1000, chunk = "records", 
   skip = rhoptions()$file.types.remove.regex, mc = lapply, textual = FALSE) {
   if (is(files, "rhwatch")) 
      files <- rhofolder(files)
   files <- rhabsolute.hdfs.path(files)
   files <- getypes(files, type, skip)
   chunksize <- as.integer(chunksize)
   handle <- .jnew("org/godhuli/rhipe/SequenceFileIterator")
   handle$init(files, as.integer(chunksize), -1L, rhoptions()$server)
   
   # a$setTextual(as.logical(textual))
   
   if (chunk == "records") {
      return(function(chunksize = chunksize) {
         if (handle$hasMoreElements()) mc(rhuz(handle$nextElement()), function(r) list(rhuz(r[[1]]), 
            rhuz(r[[2]])))
      })
   } else {
      return(function(chunksize = chunksize) {
         if (handle$hasMoreElements()) mc(rhuz(handle$nextChunk()), function(r) list(rhuz(r[[1]]), 
            rhuz(r[[2]])))
      })
   }
}
## a <- rhIterator(
## '/user/sguha/tmp/rhipe-temp-810956e1fafd30a76f869f61afa8f3e2',chunk=10) 
