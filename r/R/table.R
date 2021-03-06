# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

#' @include record-batch.R
#' @title Table class
#' @description A Table is a sequence of [chunked arrays][ChunkedArray]. They
#' have a similar interface to [record batches][RecordBatch], but they can be
#' composed from multiple record batches or chunked arrays.
#' @usage NULL
#' @format NULL
#' @docType class
#'
#' @section Factory:
#'
#' The `Table$create()` function takes the following arguments:
#'
#' * `...` arrays, chunked arrays, or R vectors, with names; alternatively,
#'    an unnamed series of [record batches][RecordBatch] may also be provided,
#'    which will be stacked as rows in the table.
#' * `schema` a [Schema], or `NULL` (the default) to infer the schema from
#'    the data in `...`
#'
#' @section S3 Methods and Usage:
#' Tables are data-frame-like, and many methods you expect to work on
#' a `data.frame` are implemented for `Table`. This includes `[`, `[[`,
#' `$`, `names`, `dim`, `nrow`, `ncol`, `head`, and `tail`. You can also pull
#' the data from an Arrow table into R with `as.data.frame()`. See the
#' examples.
#'
#' A caveat about the `$` method: because `Table` is an `R6` object,
#' `$` is also used to access the object's methods (see below). Methods take
#' precedence over the table's columns. So, `tab$Slice` would return the
#' "Slice" method function even if there were a column in the table called
#' "Slice".
#'
#' @section R6 Methods:
#' In addition to the more R-friendly S3 methods, a `Table` object has
#' the following R6 methods that map onto the underlying C++ methods:
#'
#' - `$column(i)`: Extract a `ChunkedArray` by integer position from the table
#' - `$ColumnNames()`: Get all column names (called by `names(tab)`)
#' - `$GetColumnByName(name)`: Extract a `ChunkedArray` by string name
#' - `$field(i)`: Extract a `Field` from the table schema by integer position
#' - `$SelectColumns(indices)`: Return new `Table` with specified columns, expressed as 0-based integers.
#' - `$Slice(offset, length = NULL)`: Create a zero-copy view starting at the
#'    indicated integer offset and going for the given length, or to the end
#'    of the table if `NULL`, the default.
#' - `$Take(i)`: return an `Table` with rows at positions given by
#'    integers `i`. If `i` is an Arrow `Array` or `ChunkedArray`, it will be
#'    coerced to an R vector before taking.
#' - `$Filter(i, keep_na = TRUE)`: return an `Table` with rows at positions where logical
#'    vector or Arrow boolean-type `(Chunked)Array` `i` is `TRUE`.
#' - `$serialize(output_stream, ...)`: Write the table to the given
#'    [OutputStream]
#' - `$cast(target_schema, safe = TRUE, options = cast_options(safe))`: Alter
#'    the schema of the record batch.
#'
#' There are also some active bindings:
#' - `$num_columns`
#' - `$num_rows`
#' - `$schema`
#' - `$metadata`: Returns the key-value metadata of the `Schema` as a named list.
#'    Modify or replace by assigning in (`tab$metadata <- new_metadata`).
#'    All list elements are coerced to string.
#' - `$columns`: Returns a list of `ChunkedArray`s
#' @rdname Table
#' @name Table
#' @examples
#' \donttest{
#' tab <- Table$create(name = rownames(mtcars), mtcars)
#' dim(tab)
#' dim(head(tab))
#' names(tab)
#' tab$mpg
#' tab[["cyl"]]
#' as.data.frame(tab[4:8, c("gear", "hp", "wt")])
#' }
#' @export
Table <- R6Class("Table", inherit = ArrowObject,
  public = list(
    column = function(i) {
      Table__column(self, i)
    },
    ColumnNames = function() Table__ColumnNames(self),
    RenameColumns = function(value) Table__RenameColumns(self, value),
    GetColumnByName = function(name) {
      assert_is(name, "character")
      assert_that(length(name) == 1)
      Table__GetColumnByName(self, name)
    },
    RemoveColumn = function(i) Table__RemoveColumn(self, i),
    AddColumn = function(i, new_field, value) Table__AddColumn(self, i, new_field, value),
    SetColumn = function(i, new_field, value) Table__SetColumn(self, i, new_field, value),
    field = function(i) Table__field(self, i),

    serialize = function(output_stream, ...) write_table(self, output_stream, ...),
    ToString = function() ToString_tabular(self),

    cast = function(target_schema, safe = TRUE, options = cast_options(safe)) {
      assert_is(target_schema, "Schema")
      assert_is(options, "CastOptions")
      assert_that(identical(self$schema$names, target_schema$names), msg = "incompatible schemas")
      Table__cast(self, target_schema, options)
    },

    SelectColumns = function(indices) {
      Table__SelectColumns(self, indices)
    },

    Slice = function(offset, length = NULL) {
      if (is.null(length)) {
        Table__Slice1(self, offset)
      } else {
        Table__Slice2(self, offset, length)
      }
    },
    Take = function(i) {
      if (is.numeric(i)) {
        i <- as.integer(i)
      }
      if (is.integer(i)) {
        i <- Array$create(i)
      }
      call_function("take", self, i)
    },
    Filter = function(i, keep_na = TRUE) {
      if (is.logical(i)) {
        i <- Array$create(i)
      }
      call_function("filter", self, i, options = list(keep_na = keep_na))
    },

    Equals = function(other, check_metadata = FALSE, ...) {
      inherits(other, "Table") && Table__Equals(self, other, isTRUE(check_metadata))
    },

    Validate = function() {
      Table__Validate(self)
    },

    ValidateFull = function() {
      Table__ValidateFull(self)
    },

    invalidate = function() {
      .Call(`_arrow_Table__Reset`, self)
      super$invalidate()
    }

  ),

  active = list(
    num_columns = function() Table__num_columns(self),
    num_rows = function() Table__num_rows(self),
    schema = function() Table__schema(self),
    metadata = function(new) {
      if (missing(new)) {
        # Get the metadata (from the schema)
        self$schema$metadata
      } else {
        # Set the metadata
        new <- prepare_key_value_metadata(new)
        out <- Table__ReplaceSchemaMetadata(self, new)
        # ReplaceSchemaMetadata returns a new object but we're modifying in place,
        # so swap in that new C++ object pointer into our R6 object
        self$set_pointer(out$pointer())
        self
      }
    },
    columns = function() Table__columns(self)
  )
)

arrow_attributes <- function(x, only_top_level = FALSE) {
  att <- attributes(x)

  removed_attributes <- character()
  if (identical(class(x), c("tbl_df", "tbl", "data.frame"))) {
    removed_attributes <- c("class", "row.names", "names")
  } else if (inherits(x, "data.frame")) {
    removed_attributes <- c("row.names", "names")
  } else if (inherits(x, "factor")) {
    removed_attributes <- c("class", "levels")
  } else if (inherits(x, "integer64") || inherits(x, "Date")) {
    removed_attributes <- c("class")
  } else if (inherits(x, "POSIXct")) {
    removed_attributes <- c("class", "tzone")
  } else if (inherits(x, "hms") || inherits(x, "difftime")) {
    removed_attributes <- c("class", "units")
  }

  att <- att[setdiff(names(att), removed_attributes)]
  if (isTRUE(only_top_level)) {
    return(att)
  }

  if (is.data.frame(x)) {
    columns <- map(x, arrow_attributes)
    if (length(att) || !all(map_lgl(columns, is.null))) {
      list(attributes = att, columns = columns)
    }
  } else if (length(att)) {
    list(attributes = att, columns = NULL)
  } else {
    NULL
  }
}

Table$create <- function(..., schema = NULL) {
  dots <- list2(...)
  # making sure there are always names
  if (is.null(names(dots))) {
    names(dots) <- rep_len("", length(dots))
  }
  stopifnot(length(dots) > 0)
  if (all_record_batches(dots)) {
    Table__from_record_batches(dots, schema)
  } else {
    Table__from_dots(dots, schema)
  }
}

#' @export
as.data.frame.Table <- function(x, row.names = NULL, optional = FALSE, ...) {
  df <- Table__to_dataframe(x, use_threads = option_use_threads())
  if (!is.null(r_metadata <- x$metadata$r)) {
    df <- apply_arrow_r_metadata(df, .unserialize_arrow_r_metadata(r_metadata))
  }
  df
}

#' @export
as.list.Table <- as.list.RecordBatch

#' @export
row.names.Table <- row.names.RecordBatch

#' @export
dimnames.Table <- dimnames.RecordBatch

#' @export
dim.Table <- function(x) c(x$num_rows, x$num_columns)

#' @export
names.Table <- function(x) x$ColumnNames()

#' @export
`names<-.Table` <- function(x, value) x$RenameColumns(value)

#' @export
`[.Table` <- `[.RecordBatch`

#' @export
`[[.Table` <- `[[.RecordBatch`

#' @export
`[[<-.Table` <- function(x, i, value) {
  if (!is.character(i) & !is.numeric(i)) {
    stop("'i' must be character or numeric, not ", class(i), call. = FALSE)
  } else if (is.na(i)) {
    # Catch if a NA_character or NA_integer is passed. These are caught elsewhere
    # in cpp (i.e. _arrow_RecordBatch__column_name)
    # TODO: figure out if catching in cpp like ^^^ is preferred
    stop("'i' cannot be NA", call. = FALSE)
  }

  if (is.null(value)) {
    if (is.character(i)) {
      i <- match(i, names(x))
    }
    x <- x$RemoveColumn(i - 1L)
  } else {
    if (!is.character(i)) {
      # get or create a/the column name
      if (i <= x$num_columns) {
        i <- names(x)[i]
      } else {
        i <- as.character(i)
      }
    }

    # auto-magic recycling on non-ArrowObjects
    if (!inherits(value, "ArrowObject")) {
      value <- vctrs::vec_recycle(value, x$num_rows)
    }

    # construct the field
    if (!inherits(value, "ChunkedArray")) {
      value <- chunked_array(value)
    }
    new_field <- field(i, value$type)

    if (i %in% names(x)) {
      i <- match(i, names(x)) - 1L
      x <- x$SetColumn(i, new_field, value)
    } else {
      i <- x$num_columns
      x <- x$AddColumn(i, new_field, value)
    }
  }
  x
}

#' @export
`$<-.Table` <- function(x, i, value) {
  assert_that(is.string(i))
  # We need to check if `i` is in names in case it is an active binding (e.g.
  # `metadata`, in which case we use assign to change the active binding instead
  # of the column in the table)
  if (i %in% ls(x)) {
    assign(i, value, x)
  } else {
    x[[i]] <- value
  }
  x
}

#' @export
`$.Table` <- `$.RecordBatch`

#' @export
head.Table <- head.RecordBatch

#' @export
tail.Table <- tail.RecordBatch
