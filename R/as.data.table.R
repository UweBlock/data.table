as.data.table <-function(x, keep.rownames=FALSE, ...)
{
    if (is.null(x))
        return(null.data.table())
    UseMethod("as.data.table")
}

as.data.table.default <- function(x, ...){
  setDT(as.data.frame(x, ...))[]
}

as.data.table.factor <- as.data.table.ordered <- 
as.data.table.integer <- as.data.table.numeric <- 
as.data.table.logical <- as.data.table.character <- 
as.data.table.Date <- function(x, keep.rownames=FALSE, ...) {
    if (is.matrix(x)) {
        return(as.data.table.matrix(x, ...))
    }
    tt = deparse(substitute(x))[1]
    nm = names(x)
    # FR #2356 - transfer names of named vector as "rn" column if required
    if (!identical(keep.rownames, FALSE) & !is.null(nm)) 
        x <- list(nm, unname(x))
    else x <- list(x)
    if (tt == make.names(tt)) {
        # can specify col name to keep.rownames, #575
        nm = if (length(x) == 2L) if (is.character(keep.rownames)) keep.rownames[1L] else "rn"
        setattr(x, 'names', c(nm, tt))
    }
    as.data.table.list(x, FALSE)
}

R300_provideDimnames <- function (x, sep = "", base = list(LETTERS)) {
    # backported from R3.0.0 so data.table can depend on R 2.14.0 
    dx <- dim(x)
    dnx <- dimnames(x)
    if (new <- is.null(dnx)) 
        dnx <- vector("list", length(dx))
    k <- length(M <- vapply(base, length, 1L))
    for (i in which(vapply(dnx, is.null, NA))) {
        ii <- 1L + (i - 1L)%%k
        dnx[[i]] <- make.unique(base[[ii]][1L + 0:(dx[i] - 1L)%%M[ii]], 
            sep = sep)
        new <- TRUE
    }
    if (new) 
        dimnames(x) <- dnx
    x
}

# as.data.table.table - FR #4848
as.data.table.table <- function(x, keep.rownames=FALSE, ...) {
    # Fix for bug #5408 - order of columns are different when doing as.data.table(with(DT, table(x, y)))
    val = rev(dimnames(R300_provideDimnames(x)))
    if (is.null(names(val)) || all(nchar(names(val)) == 0L)) 
        setattr(val, 'names', paste("V", rev(seq_along(val)), sep=""))
    ans <- data.table(do.call(CJ, c(val, sorted=FALSE)), N = as.vector(x))
    setcolorder(ans, c(rev(head(names(ans), -1)), "N"))
    ans
}

as.data.table.matrix <- function(x, keep.rownames=FALSE, ...) {
    if (!identical(keep.rownames, FALSE)) {
        # can specify col name to keep.rownames, #575
        ans = data.table(rn=rownames(x), x, keep.rownames=FALSE)
        if (is.character(keep.rownames))
            setnames(ans, 'rn', keep.rownames[1L])
        return(ans)
    }
    d <- dim(x)
    nrows <- d[1L]
    ir <- seq_len(nrows)
    ncols <- d[2L]
    ic <- seq_len(ncols)
    dn <- dimnames(x)
    collabs <- dn[[2L]]
    if (any(empty <- nchar(collabs) == 0L))
        collabs[empty] <- paste("V", ic, sep = "")[empty]
    value <- vector("list", ncols)
    if (mode(x) == "character") {
        # fix for #745 - A long overdue SO post: http://stackoverflow.com/questions/17691050/data-table-still-converts-strings-to-factors
        for (i in ic) value[[i]] <- x[, i]                  # <strike>for efficiency.</strike> For consistency - data.table likes and prefers "character"
    }
    else {
        for (i in ic) value[[i]] <- as.vector(x[, i])       # to drop any row.names that would otherwise be retained inside every column of the data.table
    }
    if (length(collabs) == ncols)
        setattr(value, "names", collabs)
    else
        setattr(value, "names", paste("V", ic, sep = ""))
    setattr(value,"row.names",.set_row_names(nrows))
    setattr(value,"class",c("data.table","data.frame"))
    alloc.col(value)
}

as.data.table.list <- function(x, keep.rownames=FALSE, ...) {
    if (!length(x)) return( null.data.table() )
    # fix for #833, as.data.table.list with matrix/data.frame/data.table as a list element..
    # TODO: move this entire logic (along with data.table() to C
    for (i in seq_along(x)) {
        dims = dim(x[[i]])
        if (!is.null(dims)) {
            ans = do.call("data.table", x)
            setnames(ans, make.unique(names(ans)))
            return(ans)
        }
    }
    n = vapply(x, length, 0L)
    mn = max(n)
    x = copy(x)
    idx = which(n < mn)
    if (length(idx)) {
        for (i in idx) {
            if (!is.null(x[[i]])) {# avoids warning when a list element is NULL
                if (inherits(x[[i]], "POSIXlt")) {
                    warning("POSIXlt column type detected and converted to POSIXct. We do not recommend use of POSIXlt at all because it uses 40 bytes to store one date.")
                    x[[i]] = as.POSIXct(x[[i]])
                }
                # Implementing FR #4813 - recycle with warning when nr %% nrows[i] != 0L
                if (!n[i] && mn)
                    warning("Item ", i, " is of size 0 but maximum size is ", mn, ", therefore recycled with 'NA'")
                else if (n[i] && mn %% n[i] != 0)
                    warning("Item ", i, " is of size ", n[i], " but maximum size is ", mn, " (recycled leaving a remainder of ", mn%%n[i], " items)")
                x[[i]] = rep(x[[i]], length.out=mn)
            }
        }
    }
    # fix for #842
    if (mn > 0L) {
        nz = which(n > 0L)
        xx = point(vector("list", length(nz)), seq_along(nz), x, nz)
        if (!is.null(names(x)))
            setattr(xx, 'names', names(x)[nz])
        x = xx
    }
    if (is.null(names(x))) setattr(x,"names",paste("V",seq_len(length(x)),sep=""))
    setattr(x,"row.names",.set_row_names(max(n)))
    setattr(x,"class",c("data.table","data.frame"))
    alloc.col(x)
}

# don't retain classes before "data.frame" while converting 
# from it.. like base R does. This'll break test #527 (see 
# tests and as.data.table.data.frame) I've commented #527 
# for now. This addresses #1078 and #1128
.resetclass <- function(x, class) {
    cx = class(x)
    n  = chmatch(class, cx)
    cx = unique( c("data.table", "data.frame", tail(cx, length(cx)-n)) )
}

as.data.table.data.frame <- function(x, keep.rownames=FALSE, ...) {
    if (!identical(keep.rownames, FALSE)) {
        # can specify col name to keep.rownames, #575
        ans = data.table(rn=rownames(x), x, keep.rownames=FALSE)
        if (is.character(keep.rownames))
            setnames(ans, 'rn', keep.rownames[1L])
        return(ans)
    }
    ans = copy(x)  # TO DO: change this deep copy to be shallow.
    setattr(ans,"row.names",.set_row_names(nrow(x)))

    ## NOTE: This test (#527) is no longer in effect ##
    # for nlme::groupedData which has class c("nfnGroupedData","nfGroupedData","groupedData","data.frame")
    # See test 527.
    ## 

    # fix for #1078 and #1128, see .resetclass() for explanation.
    setattr(ans, "class", .resetclass(x, "data.frame"))
    alloc.col(ans)
}

as.data.table.data.table <- function(x, ...) {
    # fix for #1078 and #1128, see .resetclass() for explanation.
    setattr(x, 'class', .resetclass(x, "data.table"))
    if (!selfrefok(x)) x = alloc.col(x) # fix for #473
    return(x)
}
