#' @importFrom methods new setGeneric
#' @importFrom forcats fct_explicit_na
#' @importFrom data.table as.data.table tstrsplit melt

#' @exportMethod as.magpie
setGeneric("as.magpie", function(x,...)standardGeneric("as.magpie"))

setMethod("as.magpie",signature(x = "magpie"),function (x) return(x))


tmpfilter <- function(x,sep=".", replacement="_") {
  .tmpfilter <- function(x, sep=".", replacement="_") {
    .tmp <- function(x, sep, replacement) {
      if(sep!=replacement) x <- gsub(sep, replacement, x, fixed = TRUE, useBytes = TRUE)  
      x[x==""] <- " "
      return(x)
    }
    if(is.factor(x)) {
      levels(x) <- .tmp(levels(x), sep, replacement)
    } else if(is.character(x)) {
      x <- .tmp(x, sep, replacement)
    }
    return(x)
  }
  cl <- class(x)
  cn <- colnames(x)
  rn <- rownames(x)
  x <- as.data.frame(lapply(x, .tmpfilter, sep=sep, replacement=replacement))
  colnames(x) <- cn
  rownames(x) <- rn
  class(x) <- cl
  return(x)
}

setMethod("as.magpie",
          signature(x = "lpj"),
          function (x, unit="unknown", ...)
          {
            xdimnames <- dimnames(x)
            xdim <- dim(x)
            x <- array(x[magclassdata$half_deg$lpj_index,,,],dim=c(dim(x)[1:2],dim(x)[3]*dim(x)[4]))
            dimnames(x) <- list(paste(magclassdata$half_deg$region,1:59199,sep='.'),
                                xdimnames[[2]],
                                paste(rep(xdimnames[[3]],xdim[4]),rep(xdimnames[[4]],each=xdim[3]),sep="."))
            out <- new("magpie",x)
            return(updateMetadata(out,unit=unit))
          }
)

setMethod("as.magpie",
    signature(x = "array"),
    function (x, spatial=NULL, temporal=NULL, unit="unknown", ...)
    {
      store_attributes <- copy.attributes(x,0)

      # Add the sets as name to the dimnames, if existent
      if(is.null(names(dimnames(x))) & !is.null(attr(x,"sets"))){
        tmp<-dimnames(x)
        names(tmp)<-attr(x,"sets")
        dimnames(x)<-tmp
      }
      #This part of the function analyses what structure the input has
      d <- list()  #list of dimension types found in the array
      if(!is.null(temporal)) d$temporal <- temporal
      if(!is.null(spatial)) d$regiospatial <- spatial
      for(i in 1:length(dim(x))) {
        if(!is.null(dimnames(x)[[i]])) {
          if(is.null(spatial)) {
            if(length(grep("^(([A-Z]{3})|(glob))$",dimnames(x)[[i]]))==dim(x)[i])    d$regional <- c(d$regional,i)  #regional information
            if(length(grep("^[A-Z]+[\\._][0-9]+$",dimnames(x)[[i]]))==dim(x)[i]) d$regiospatial <- c(d$regiospatial,i)  #regio-spatial information
          }
          if(is.null(temporal)) {
            if(is.temporal(dimnames(x)[[i]]))     d$temporal <- c(d$temporal,i) #temporal information
          }
        } else if(dim(x)[i]==1)                   d$nothing <- c(d$nothing,i)   #dimension with no content
      }

      if(!is.null(spatial)) {
        if(spatial==0) {
          d$regiospatial <- NULL
          d$regional <- NULL
        }
      }

      if(!is.null(temporal)) {
        if(temporal==0) {
          d$temporal <- NULL
        }
      }

      #Write warning when any type (except type "nothing") is found more than once
      tmp <- lapply(d,length)>1; tmp <- tmp[names(tmp)!="nothing"]
      if(any(tmp)==TRUE) warning("No clear mapping of dimensions to dimension types. First detected possibility is used! Please use arguments temporal and spatial to specify which dimensions are what!")
      for(i in which(tmp)) {
        d[[i]] <- d[[i]][1]
      }

      #If a regional dimension exists, test whether "glob" appears in the dimnames and rename it with "GLO"
      if(!is.null(d$regional)) {
        for(i in d$regional) {
          dimnames(x)[[i]] <- sub("^glob$","GLO",dimnames(x)[[i]])
        }
      }

      #make sure that temporal dimension uses dimnames of the form y0000
      if(!is.null(d$temporal)) {
        for(i in d$temporal) {
          dimnames(x)[[i]] <- sub("^[a-z]?([0-9]{4})$","y\\1",dimnames(x)[[i]])
        }
      }

      #make sure that spatial dimension uses dimnames of the form XXX.123
      if(!is.null(d$regiospatial)) {
        for(i in d$regiospatial) {
          ntmp <- names(dimnames(x))[1]
          if(!is.null(ntmp)) if(!is.na(ntmp)) if(names(dimnames(x))[1] == "j") names(dimnames(x))[1] <- "i.j"
          #dimnames(x)[[i]] <- sub("_","\\.",dimnames(x)[[i]])
        }
      }


      #If no temporal dimension is defined, but a dimension of type nothing exists, use this dimension as temporal dimension
      if(is.null(d$temporal)) {
        if(length(d$nothing)>0) {
          d$temporal <- d$nothing[1]
          d$nothing <- d$nothing[-1]
          if(length(d$nothing)==0) d$nothing <- NULL
        } else {
          d$temporal <- 0
        }
      }

      #try to create regiospatial dimension if possible
      if(is.null(d[["regiospatial"]])) {
          #regional dimension exists
        if(!is.null(d$regional))  {
          #dimnames(x)[[d$regional]] <- paste(dimnames(x)[[d$regional]],1:dim(x)[d$regional],sep=".")
          d$regiospatial <- d$regional
        } else {
          d$regiospatial <- 0
        }
      }
      d$regional <- NULL

      #Starting from here d$temporal and d$regiospatial should be defined both
      #If any of these two could neither be found nor created the value should be 0

      if(d$regiospatial==0) {
        if(is.null(dimnames(x))) {
          x <- array(x,c(dim(x),1))
          dimnames(x)[[length(dim(x))]] <- list("GLO")
        } else {
          x <- array(x,c(dim(x),1),c(dimnames(x),"GLO"))
        }
        d$regiospatial <- length(dim(x))
      }

      if(d$temporal==0) {
        x <- array(x,c(dim(x),1),c(dimnames(x),NULL))
        d$temporal <- length(dim(x))
      }

      #Check if third dimension exists. If not, create it
      if(length(dim(x))==2) {
        x <- array(x,c(dim(x),1),c(dimnames(x),NULL))
      }

      #Now temporal and regiospatial dimension should both exist
      #Return MAgPIE object
      out <- copy.attributes(store_attributes,new("magpie",wrap(x,list(d$regiospatial,d$temporal,NA))))
      return(updateMetadata(out, unit=unit))
    }
)

setMethod("as.magpie",
    signature(x = "numeric"),
    function(x, unit="unknown", ...)
    {
      out <- copy.attributes(x,as.magpie(as.array(x),...))
      return(updateMetadata(out, unit=unit))
    }
)

setMethod("as.magpie",
    signature(x = "NULL"),
    function (x)
    {
      return(NULL)
    }
)

setMethod("as.magpie",
          signature(x = "data.frame"),
          function (x, datacol=NULL, tidy=FALSE, sep=".", replacement="_", unit="unknown", filter=TRUE, ...)
          {
            # filter illegal characters
            if(isTRUE(filter)) {
              x <- tmpfilter(x, sep=sep, replacement=replacement)
            }
            
            if(tidy) return(tidy2magpie(x,...))
            if(dim(x)[1]==0) return(copy.attributes(x,new.magpie(NULL)))
            if(is.null(datacol)) {
              is.numericlike <- function(x) {
                .tmp <- function(x) return(all(!is.na(suppressWarnings(as.numeric(x[!is.na(x)])))))
                if(isFALSE(.tmp(x[1]))) return(FALSE)
                return(.tmp(x))
              }
              for(i in dim(x)[2]:1) {
                if(!is.factor(x[[i]]) && is.numericlike(x[[i]]) && !is.temporal(x[[i]])) {
                  datacol <- i
                } else {
                  break
                }
              }
            }
            if(!is.null(datacol)) {
              if(datacol==1) return(copy.attributes(x,as.magpie(as.matrix(x),...)))
              if(datacol==dim(x)[2]) return(tidy2magpie(x,...))
              x[[datacol-1]] <- as.factor(x[[datacol-1]])
            }
            if (!requireNamespace("reshape2", quietly = TRUE)) stop("The package reshape2 is required for as.magpie applied on non-tidy data.frames!")
            out <- copy.attributes(x,tidy2magpie(suppressMessages(reshape2::melt(x)),...))
            return(updateMetadata(out, unit=unit))
          }
)

setMethod("as.magpie",
          signature(x = "quitte"),
          function(x, sep=".", replacement="_", filter=TRUE, ...)
          {
              is.quitte <- function(x, warn=FALSE) {
                  # object is not formally defined as quitte class
                  if(!methods::is(x,"quitte")) return(FALSE)

                  # object is formally defined as quitte but it has to
                  # be checked whether it follows all structural
                  # rules of a quitte object

                  # are all mandatory columns included?
                  mandatory_columns <- c("model","scenario","region","variable","unit","period","value")
                  if(!all(mandatory_columns %in% names(x))) {
                      if(warn) warning("Object formally defined as quitte object, but it does not contain all required columns (missing: ",paste(mandatory_columns[!(mandatory_columns %in% names(x))],collapse=", "),")!")
                      return(FALSE)
                  }

                  # are all columns factors which have to be factors?
                  factor_columns <- sapply(x[c("model","scenario","region","variable","unit")],is.factor)
                  if(!all(factor_columns)) {
                      if(warn) warning("Object formally defined as quitte object, but there are columns not stored as factor which actually have to be stored that way (no factor: ",paste(names(factor_columns)[!factor_columns],collapse=", "),")!")
                      return(FALSE)
                  }

                  #is the value column of type numeric?
                  if(!is.numeric(x$value)) {
                      if(warn) warning("Object formally defined as quitte object, but value column is not of type numeric!")
                      return(FALSE)
                  }

                  #is period column of type POSIXct?
                  if(!methods::is(x$period,"POSIXct") && !is.integer(x$period)) {
                      if(warn) warning("Object formally defined as quitte object, but period column is neither integer nor of type POSIXct!")
                      return(FALSE)
                  }

                  return(TRUE)
              }

            if(!is.quitte(x)) {
              warning("Input does not follow the full quitte class definition! Fallback to data.frame conversion.")
              class(x) <- "data.frame"
              return(as.magpie(x,...))
            }
            x$period <- format(x$period, format = "y%Y")
            # filter illegal characters
            
            if(isTRUE(filter)) {
              x <- tmpfilter(x, sep=sep, replacement=replacement)
            }
            
            if(length(grep("^cell$",names(x),ignore.case=TRUE)) > 0) {
              i <- grep("^cell$",names(x),ignore.case=TRUE,value=TRUE)
              x$region <- paste(x$region,x[[i]],sep=".")
              x <- x[names(x)!=i]
            }
            # remove NA columns
            # and <NA> columns that have been replaced by 
            # forcats::fct_explicit_na()
            na_string <- formals(fct_explicit_na)[['na_level']]
            x <- x[colSums(!(na_string == x | is.na(x))) != 0]

            #put value column as last column
            x <- x[c(which(names(x)!="value"),which(names(x)=="value"))]
            out <- tidy2magpie(x,spatial="region",temporal="period")
            return(updateMetadata(out))
          }
)

setMethod("as.magpie",
          signature(x = "tbl_df"),
          function(x, unit="unknown", ...)
          {
            if("quitte" %in% class(x)) {
              class(x) <- c("quitte","data.frame")
              out <- as.magpie(x,...)
              return(updateMetadata(out))
            } else {
              class(x) <- "data.frame"
              out <- as.magpie(x,...)
              return(updateMetadata(out, unit=unit))
            }
          }
)

setMethod("as.magpie",
          signature(x = "RasterBrick"),
          function(x, unit="unknown", ...)
          {
            if (!requireNamespace("raster", quietly = TRUE)) stop("The package \"raster\" is required for conversion of raster objects!")
            df <- as.data.frame(x,na.rm=TRUE)
            co <- raster::coordinates(x)[as.integer(rownames(df)),]
            co <- matrix(sub(".","p",co,fixed=TRUE),ncol=2)
            colnames(co) <- c("x","y")
            df <- as.data.table(cbind(co,df))
            df <- melt(df, id.vars=c("x","y"))
            variable <- as.data.table(tstrsplit(df$variable,"..",fixed=TRUE))
            if(ncol(variable)==1) {
              names(variable) <- "data"
              temporal <- NULL
            } else if(ncol(variable)==2) {
              names(variable) <- c("year","data")
              temporal <- 3
            } else {
              stop("Reserved dimension separator \"..\" occurred more than once in layer names! Cannot convert raster object")
            }
            df <- cbind(df[,1:2],variable,df[,4])
            out <- tidy2magpie(df, spatial=1:2, temporal=temporal)
            return(updateMetadata(out, unit=unit))
          }
)
