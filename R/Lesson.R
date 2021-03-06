#' Class to contain a single Lesson by the Carpentries
#'
#' @description
#' This is a wrapper for several [Episode] class objects.
#' @details
#' Lessons are made of up several episodes within the `_episodes/` directory of
#' a lesson. This class keeps track of several episodes and allows us to switch
#' between RMarkdown and markdown episodes
#' @export
Lesson <- R6::R6Class("Lesson",
  public = list(

    #' @field path \[`character`\] path to Lesson directory
    path = NULL,

    #' @field episodes \[`list`\] list of [Episode] class objects representing
    #'   the episodes of the lesson.
    episodes = NULL,

    #' @field extra \[`list`\] list of [Episode] class objects representing
    #'   the extra markdown components including index, setup, information
    #'   for learners, information for instructors, and learner profiles. This
    #'   is not processed for the jekyll lessons.
    extra = NULL,

    #' @field rmd \[`logical`\] when `TRUE`, the episodes represent RMarkdown
    #'   files, default is `FALSE` for markdown files.
    rmd = FALSE,

    #' @description create a new Lesson object from a directory
    #' @param path \[`character`\] path to a lesson directory. This must have a
    #'   folder called `_episodes` within that contains markdown episodes
    #' @param rmd \[`logical`\] when `TRUE`, the imported files will be the
    #'   source RMarkdown files. Defaults to `FALSE`, which reads the rendered
    #'   markdown files.
    #' @param jekyll \[`logical`\] when `TRUE` (default), the structure of the
    #'   lesson is assumed to be derived from the carpentries/styles repository.
    #'   When `FALSE`, The structure is assumed to be a {sandpaper} lesson and
    #'   extra content for learners, instructors, and profiles will be populated.
    #' @param ... arguments passed on to [Episode$new][Episode]
    #' @return a new Lesson object that contains a list of [Episode] objects in
    #' `$episodes`
    #' @examples
    #' frg <- Lesson$new(lesson_fragment())
    #' frg$path
    #' frg$episodes
    initialize = function(path = NULL, rmd = FALSE, jekyll = TRUE, ...) {
      stop_if_no_path(path)
      if (jekyll) {
        jeky <- read_jekyll_episodes(path, rmd, ...)
        self$episodes <- jeky$episodes
        self$rmd <- jeky$rmd
      } else {
        # Modern lessons do not need to have tags processed because there are 
        # no tags!!!
        episode_path <- fs::path(path, "episodes")
        extra_paths <- fs::path(path, c("instructors", "learners", "profiles"))
        cfg <- fs::dir_ls(path, regexp = "config[.]ya?ml")

        self$episodes <- read_markdown_files(
          episode_path, cfg, process_tags = FALSE, ...)

        standard_files <- read_markdown_files(path, process_tags = FALSE, ...)

        extra_files <- purrr::flatten(purrr::map(extra_paths,
          read_markdown_files, cfg, process_tags = FALSE, ...))

        self$extra <- c(standard_files, extra_files)

      }
      self$path <- path
    },

    #' @description
    #' Gather all of the blocks from the lesson in a list of xml_nodeset objects
    #' @param body the XML body of a carpentries lesson (an xml2 object)
    #' @param type the type of block quote in the Jekyll syntax like ".challenge",
    #'   ".discussion", or ".solution"
    #' @param level the level of the block within the document. Defaults to `0`,
    #'   which represents all of the block_quotes within the document regardless
    #'   of nesting level.
    #' @param path \[`logical`\] if `TRUE`, the names of each element
    #'   will be equivalent to the path. The default is `FALSE`, which gives the
    #'   name of each episode.
    blocks = function(type = NULL, level = 0, path = FALSE) {
      nms <-  if (path) purrr::map(self$episodes, "path") else names(self$episodes)
      res <- purrr::map(self$episodes, ~.x$get_blocks(type = type, level = level))
      names(res) <- nms
      return(res)
    },

    #' @description
    #' Gather all of the challenges from the lesson in a list of xml_nodeset objects
    #' @param path \[`logical`\] if `TRUE`, the names of each element
    #'   will be equivalent to the path. The default is `FALSE`, which gives the
    #'   name of each episode.
    #' @param graph \[`logical`\] if `TRUE`, the output will be a data frame
    #'   representing the directed graph of elements within the challenges. See
    #'   the `get_challenge_graph()` method in [Episode].
    #' @param recurse \[`logical`\] when `graph = TRUE`, this will include the
    #'   solutions in the output. See [Episode] for more details.
    challenges = function(path = FALSE, graph = FALSE, recurse = TRUE) {
      nms <-  if (path) purrr::map(self$episodes, "path") else names(self$episodes)
      eps <- self$episodes
      names(eps) <- nms
      if (graph) {
        res <- purrr::map_dfr(eps, ~.x$get_challenge_graph(recurse), .id = "Episode")
      } else {
        res <- purrr::map(eps, "challenges")
      }
      return(res)
    },

    #' @description
    #' Gather all of the solutions from the lesson in a list of xml_nodeset objects
    #' @param path \[`logical`\] if `TRUE`, the names of each element
    #'   will be equivalent to the path. The default is `FALSE`, which gives the
    #'   name of each episode.
    solutions = function(path = FALSE) {
      nms <-  if (path) purrr::map(self$episodes, "path") else names(self$episodes)
      res <- purrr::map(self$episodes, "solutions")
      names(res) <- nms
      return(res)
    },

    #' @description
    #' Remove episodes that have no challenges
    #' @param verbose \[`logical`\] if `TRUE` (default), the names of each
    #'   episode removed is reported. Set to `FALSE` to remove this behavior.
    #' @return the Lesson object, invisibly
    #' @examples
    #' frg <- Lesson$new(lesson_fragment())
    #' frg$thin()
    thin = function(verbose = TRUE) {
      if (verbose) {
        to_remove <- lengths(self$challenges()) == 0
        if (sum(to_remove) > 0) {
          nms <- glue::glue_collapse(names(to_remove)[to_remove], sep = ", ", last = ", and ")
          epis <- if (sum(to_remove) > 1) "episodes" else "episode"
          message(glue::glue("Removing {sum(to_remove)} {epis}: {nms}"))
          self$episodes[to_remove] <- NULL
        } else {
          message("Nothing to remove!")
        }
      } else {
        self$episodes[lengths(self$challenges()) == 0] <- NULL
      }
      invisible(self)
    },

    #' @description
    #' Re-read all Episodes from disk
    #' @return the Lesson object
    #' @examples
    #' frg <- Lesson$new(lesson_fragment())
    #' frg$episodes[[1]]$body
    #' frg$isolate_blocks()$episodes[[1]]$body # empty
    #' frg$reset()$episodes[[1]]$body # reset
    reset = function() {
      self$initialize(self$path)
      return(invisible(self))
    },

    #' @description
    #' Remove all elements except for those within block quotes that have a
    #' kramdown tag. Note that this is a destructive process.
    #' @return the Episode object, invisibly
    #' @examples
    #' frg <- Lesson$new(lesson_fragment())
    #' frg$isolate_blocks()$body # only one challenge block_quote
    isolate_blocks = function() {
      purrr::walk(self$episodes, ~.x$isolate_blocks())
      invisible(self)
    },

    #' @description
    #' Validate that the heading elements meet minimum accessibility requirements
    #' @return TRUE if the headings are valid, FALSE if otherwise with
    #'   user-level messages.
    validate_headings = function() {
      
    }
  ),
  active = list(

    #' @field n_problems number of problems per episode
    n_problems = function() {
      purrr::map_int(self$episodes, ~length(.x$show_problems))
    },

    #' @field show_problems contents of the problems per episode
    show_problems = function() {
      res <- purrr::map(self$episodes, "show_problems")
      res[purrr::map_lgl(res, ~length(.x) > 0)]
    },

    #' @field files the source files for each episode
    files = function() {
      purrr::map_chr(self$episodes, "path")
    }
  ),
  private = list(
    deep_clone = function(name, value) {
      if (name == "episodes") {
        purrr::map(value, ~.x$clone(deep = TRUE))
      } else {
        value
      }
    }
  )
)
