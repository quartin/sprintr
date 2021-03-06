jira_url <- function() {
  endpoint <- Sys.getenv('JIRA_API_URL', "")
  if (endpoint == "") stop("Jira API url not found.", .call = FALSE) else endpoint
}

jira_username <- function() {
  user <- Sys.getenv('JIRA_USER', "")
  if (user == "") stop("Jira API user not found.", .call = FALSE) else user
}

jira_token <- function() {
  token <- Sys.getenv('JIRA_API_KEY', "")
  if (token == "") stop("Jira API key not found.", .call = FALSE) else token
}

#' Title
#'
#' @param path API endpoint to retrieve
#'
#' @return A jira_api object
#' @export
#'
#' @importFrom httr modify_url GET http_type accept_json authenticate content
#' @importFrom jsonlite fromJSON
#'
#' @examples
#' NULL
jira_api <- function(path) {
  url <- httr::modify_url(jira_url(), path = path)
  resp <- httr::GET(url, httr::accept_json(),
                    httr::authenticate(jira_username(), jira_token()))
  if (httr::http_type(resp) != "application/json") {
    stop("API did not return json", call. = FALSE)
  }

  parsed <- jsonlite::fromJSON(httr::content(resp, "text"), simplifyVector = TRUE)

  structure(
    list(
      content = parsed,
      path = path,
      response = resp
    ),
    class = "jira_api"
  )
}

#' Title
#'
#' @param path API endpoint to retrieve
#' @param post_data List of data to post to API
#'
#' @return A jira_api object
#' @export
#'
#' @importFrom httr modify_url POST http_type accept_json authenticate content
#' @importFrom jsonlite fromJSON
#'
#' @examples
#' NULL
jira_api_post <- function(path, post_data) {
  url <- httr::modify_url(jira_url(), path = path)
  resp <- httr::POST(url, httr::accept_json(),
                     httr::authenticate(jira_username(), jira_token()),
               body = post_data, encode = "json")
  if (httr::http_type(resp) != "application/json") {
    stop("API did not return json", call. = FALSE)
  }
  parsed <- jsonlite::fromJSON(httr::content(resp, "text"), simplifyVector = TRUE)

  structure(
    list(
      content = parsed,
      path = path,
      response = resp
    ),
    class = "jira_api"
  )
}

print.jira_api <- function(x, ...) {
  cat("<JIRA ", x$path, ">\n", sep = "")
  utils::str(x$content)
  invisible(x)
}

#' Title
#'
#' @return dataframe
#' @export
#'
#' @importFrom dplyr bind_cols select
#' @importFrom purrr pluck
#' @importFrom rlang .data
#'
#' @examples
#' NULL
get_fields <- function() {
  all_fields <- jira_api("/rest/api/3/field")$content
  dplyr::bind_cols(dplyr::select(all_fields, -.data$schema),
                   purrr::pluck(all_fields, "schema"))
}

#' Title
#'
#' @return dataframe
#' @export
#'
#' @importFrom dplyr bind_cols bind_rows data_frame select
#' @importFrom purrr pluck
#' @importFrom rlang .data
#' @importFrom glue glue
#'
#' @examples
#' NULL
get_boards <- function() {
  content <- list(isLast = FALSE,
                  startAt = 0,
                  maxResults = 0)

  all_boards <- dplyr::data_frame()

  while (!content$isLast) {
    start_at <- content$startAt + content$maxResults
    url <- glue::glue("/rest/agile/1.0/board/?",
                      "startAt={start_at}")

    content <- jira_api(url) %>%
      purrr::pluck("content")

    values <- purrr::pluck(content, "values")

    boards <- dplyr::bind_cols(dplyr::select(values, -.data$location),
                                   purrr::pluck(values, "location"))

    all_boards <- dplyr::bind_rows(all_boards, boards)
  }
  all_boards
}

#' Title
#'
#' @param board_id ID of sprint board to retrieve
#'
#' @return dataframe
#' @export
#'
#' @importFrom glue glue
#' @importFrom purrr pluck
#' @importFrom tibble as.tibble
#'
#' @examples
#' NULL
get_board_details <- function(board_id) {
  jira_api(glue::glue("/rest/agile/1.0/sprint/{board_id}")) %>%
    purrr::pluck("content") %>% tibble::as.tibble()
}

#' Title
#'
#' @param board_id ID of sprint board to retrieve
#'
#' @return dataframe
#' @export
#'
#' @importFrom dplyr bind_rows
#' @importFrom glue glue
#' @importFrom purrr pluck
#'
#' @examples
#' NULL
get_sprints <- function(board_id) {
  start_at <- 0
  resp <- jira_api(glue::glue("/rest/agile/1.0/board/{board_id}/sprint?",
                              "startAt={start_at}&maxResults=50"))
  resp_values <- resp %>% purrr::pluck("content", "values")
  #browser()
  while (resp$content$isLast == FALSE) {
    start_at <- start_at + 50
    resp <- jira_api(glue::glue("/rest/agile/1.0/board/{board_id}/sprint?",
                                "startAt={start_at}&maxResults=50"))
    resp_values <- dplyr::bind_rows(resp_values,
                                    purrr::pluck(resp, "content", "values"))

  }
  resp_values
}

#' Title
#'
#' @param sprint_id ID of sprint to retrieve
#'
#' @return dataframe
#' @export
#'
#' @importFrom glue glue
#' @importFrom purrr discard pluck keep flatten_df map splice
#' @importFrom stringr str_detect
#'
#' @examples
#' NULL
get_sprint_report <- function(sprint_id) {
  sprint_report <- jira_api(
    glue::glue("/rest/greenhopper/1.0/rapid/charts/sprintreport?",
               "rapidViewId=8&sprintId={sprint_id}")) %>%
    purrr::pluck("content", "contents")
  discard_list <- names(sprint_report) %>%
    stringr::str_detect(pattern = "Sum")
  clean_report <- purrr::discard(sprint_report, discard_list)
  point_sums <- purrr::keep(sprint_report, discard_list) %>%
    purrr::map("value") %>% purrr::flatten_df()
  purrr::splice(clean_report, list(points_sum = point_sums))
}

#' Title
#'
#' @param issue_key Key of issue to retrieve
#' @param full_response Return raw list of fields
#'
#' @return dataframe
#' @export
#'
#' @examples
#' NULL
get_issue <- function(issue_key, full_response = FALSE) {
  resp <- jira_api(glue::glue("/rest/agile/1.0/issue/{issue_key}")) %>%
    purrr::pluck("content", "fields")
  if (!full_response) {
    tibble::tibble(
      key = issue_key,
      story_points = purrr::pluck(resp, "customfield_10013",
                                  .default = NA_integer_),
      epic_name = purrr::pluck(resp, "customfield_10011",
                               .default = NA_character_),
      program = purrr::pluck(resp, "customfield_10500", "value",
                             .default = NA_character_)
    )
  } else {
    resp
  }
}

#' Title
#'
#' @param board_id ID of board to retrieve
#'
#' @return dataframe
#' @export
#'
#' @examples
#' NULL
get_issues_on_backlog <- function(board_id) {
  start_at <- 0
  resp <- jira_api(glue::glue("/rest/agile/1.0/board/{board_id}/backlog",
                              "?startAt={start_at}"))
  resp_values <- resp %>% purrr::pluck("content", "issues", "fields")
  while (resp$content$startAt + resp$content$maxResults < resp$content$total) {
    start_at <- start_at + 50
    resp <- jira_api(glue::glue("/rest/agile/1.0/board/{board_id}/backlog?",
                                "startAt={start_at}&maxResults=50"))
    resp_values <- dplyr::bind_rows(resp_values,
                                    purrr::pluck(resp, "content", "issues", "fields"))
  }

  resp_values
}

#' Title
#'
#' @param response HTTR response
#'
#' @return dataframe
#' @export
#'
#' @importFrom tibble tibble
#'
#' @examples
#' NULL
parse_issue <- function(response) {
  tibble::tibble(
    key = "DUMMY",
    story_points = purrr::pluck(response, "customfield_10013",
                                .default = NA_integer_),
    epic_name = purrr::pluck(response, "customfield_10011",
                             .default = NA_character_),
    program = purrr::pluck(response, "customfield_10500", "value",
                           .default = NA_character_)
  )
}

#' Title
#'
#' @param sprint_id ID of the sprint to pull issue-level details on
#'
#' @return A dataframe
#' @export
#' @importFrom dplyr mutate bind_rows
#' @importFrom purrr map_dfr
#'
#' @examples
#' NULL
get_sprint_report_detail <- function(sprint_id) {
  sprint_report <- get_sprint_report(sprint_id = sprint_id)
  sprint_report$completedIssues$key %>%
    purrr::map_dfr(function(x) get_issue(issue_key = x)) %>%
    dplyr::mutate(type = "completed") -> comp_issues
  sprint_report$issuesNotCompletedInCurrentSprint$key %>%
    purrr::map_dfr(function(x) get_issue(issue_key = x)) %>%
    dplyr::mutate(type = "incomplete") -> incomp_issues
  sprint_report$puntedIssues$key %>%
    purrr::map_dfr(function(x) get_issue(issue_key = x)) %>%
    dplyr::mutate(type = "removed") -> removed_issues
  sprint_report$issueKeysAddedDuringSprint %>% names() %>%
    purrr::map_dfr(function(x) get_issue(issue_key = x)) %>%
    dplyr::mutate(type = "added") -> added_issues
  sprint_report_detail <- dplyr::bind_rows(comp_issues, incomp_issues,
                                    removed_issues, added_issues) %>%
    dplyr::mutate(sprint_id = sprint_id)
  sprint_report_detail
}
