# =============================================================================
# data_cleaning.R
# Input : data/TS-Nudging-Data.xlsx  (shared data file, sheet "Sheet1",
#                                     one row per participant)
# Output: data/cleaned_data.rda      (objects: wide, long)
#   wide : one row per participant
#   long : one row per participant x experimental round
#
# The data file contains only the survey columns used below; browser,
# recruitment, and navigation metadata from the survey platform are not included.
#
# Note on the AI chat data: to protect participants' privacy, the shared data
# file does not contain the text of the messages exchanged with the AI
# assistant. Instead, it contains counts derived from the chat logs:
#   round1_ai_n ... round5_ai_n : number of messages the participant sent to the
#                                 assistant in each round
#   ai_msg_bad    : number of messages with fewer than 5 characters or without a
#                   word of at least two letters
#   ai_msg_repeat : TRUE if the participant sent an identical message more than once
# These counts define assistant use (messages per round and per session) and the
# AI-chat component of the quality score.
# =============================================================================
RAW_FILE <- file.path("data", "TS-Nudging-Data.xlsx")
OUT_FILE <- file.path("data", "cleaned_data.rda")

## ---- design constants --------------------------------------------------------
ROUNDS <- 1:5
LIKERT_COLS <- c("chart_comfort", "risk_tolerance", "quick_decisions",
                 "ai_comfort", "ai_predictable", "ai_trust",
                 "round2_confidence", "round4_confidence")
AI_ATTITUDE_COLS <- c("ai_trust", "ai_predictable", "ai_comfort")
AGE_MIDPOINTS <- c("18-24" = 21, "25-34" = 29.5, "35-44" = 39.5, "45-54" = 49.5, "55-64" = 59.5, "65+" = 70)

# attention / comprehension checks
ATTN_ANSWERS <- list(attention_action = "HOLD", probability_check = c(5, 0.05, 0.005, 0.5), price_drop = 90)

# quality score: weights and flags
QSCORE_WEIGHTS <- c(attention = 0.70, comp_time = 0.10, straightline = 0.10, ai_chat = 0.10)
FAST_THRESHOLD_MIN <- 2
SLOW_THRESHOLD_MIN <- 60
FAST_DECISION_SEC  <- 1.5

# Armenian answer labels -> English
DEMO_TRANSLATE <- list(
  gender = c("Իգական" = "Female", "Արական" = "Male", "Նախընտրում եմ չնշել" = "Prefer not to say"),
  nationality = c("Հայ" = "Armenian", "Ռուս" = "Russian", "Ամերիկացի" = "American",
                  "Ֆրանսիացի" = "French", "Գերմանացի" = "German", "Իտալացի" = "Italian",
                  "Իսպանացի" = "Spanish", "Չինացի" = "Chinese", "Հնդիկ" = "Indian",
                  "Իրանցի" = "Iranian", "Վրացի" = "Georgian", "Այլ" = "Other"),
  education = c("Միջնակարգ" = "High school", "Բակալավրիատ" = "Bachelor's",
                "Մագիստրատուրա" = "Master's", "Ասպիրանտուրա (PhD)" = "PhD", "Այլ" = "Other"),
  field = c("ԳՏՃՄ (STEM)" = "STEM", "Բիզնես / Տնտեսագիտություն" = "Business / Economics",
            "Հասարակական գիտություններ" = "Social Sciences",
            "Արվեստ / Հումանիտար գիտություններ" = "Arts / Humanities", "Այլ" = "Other"),
  employment = c("Բակալավրիատի / մագիստրատուրայի ուսանող" = "Bachelor/Master student",
                 "Ասպիրանտ" = "PhD student", "Հետազոտող / Դասախոս" = "Researcher / Lecturer",
                 "Աշխատող" = "Employed", "Ինքնազբաղված / Բիզնեսի սեփականատեր" = "Self-employed / Business owner",
                 "Գործազուրկ" = "Unemployed", "Թոշակառու" = "Retired", "Այլ" = "Other"),
  news_frequency = c("Ամեն օր" = "Daily", "Ամեն շաբաթ" = "Weekly", "Ամեն ամիս" = "Monthly",
                     "Հազվադեպ" = "Rarely", "Երբեք" = "Never"))

# experiment key -> condition and target action
# BUY_SELL: either Buy or Sell counts as the target action (active trade)
EXP_TO_CONDITION <- c(
  statusquo = "status_quo", decoyNo = "decoy_no", decoyYes = "decoy_yes", middle = "middle",
  scarcityInc = "rare_event", scarcityDec = "rare_event",
  framing70 = "framing_text", framing30 = "framing_text",
  framinggreen = "framing_visual", framingred = "framing_visual",
  herdbuy = "herd", herdsell = "herd",
  anchoringhigh = "anchoring", anchoringlow = "anchoring", timelimit = "time_limit")
NUDGE_TARGET <- c(
  statusquo = "BUY_SELL", decoyNo = "SELL", decoyYes = "BUY", middle = "HOLD",
  scarcityInc = "BUY", scarcityDec = "SELL", framing70 = "BUY", framing30 = "SELL",
  framinggreen = "BUY", framingred = "SELL", herdbuy = "BUY", herdsell = "SELL",
  anchoringhigh = "BUY", anchoringlow = "SELL", timelimit = "BUY_SELL")

## ---- helpers -----------------------------------------------------------------
is_blank <- function(x) is.na(x) | !nzchar(trimws(as.character(x))) |
  toupper(trimws(as.character(x))) %in% c("NA", "NULL", "N/A") | trimws(as.character(x)) == "_"
to_time <- function(v) { v <- as.character(v); v[is_blank(v)] <- NA
  suppressWarnings(as.POSIXct(v, tz = "Asia/Yerevan", format = "%Y-%m-%d %H:%M:%OS")) }
secs <- function(to, from) { s <- as.numeric(difftime(to_time(to), to_time(from), units = "secs")); s[s < 0] <- NA; s }
num  <- function(x) { x <- as.character(x); x[is_blank(x)] <- NA; suppressWarnings(as.numeric(x)) }
translate <- function(x, map) { x <- trimws(as.character(x)); x[is_blank(x)] <- NA
  hit <- x %in% names(map); x[hit] <- unname(map[x[hit]]); x }
parse_likert <- function(x) { x <- as.character(x); x[is.na(x) | x %in% c("_", "", "NA", "NULL")] <- NA
  suppressWarnings(as.numeric(sub("^([0-9]+).*$", "\\1", x))) }
hits_target <- function(action, target) {
  action <- toupper(trimws(as.character(action))); target <- as.character(target)
  as.integer(!is.na(target) & !is.na(action) &
               (action == target | (target == "BUY_SELL" & action %in% c("BUY", "SELL")))) }

## ---- import ------------------------------------------------------------------
raw <- as.data.frame(readxl::read_excel(RAW_FILE, sheet = "Sheet1", col_types = "text"))
raw <- raw[!is_blank(raw$participant_id) & !is_blank(raw$bibd_participant_index), , drop = FALSE]

## ---- participant-level variables --------------------------------------------
wide <- data.frame(
  participant_id         = raw$participant_id,
  bibd_participant_index = as.integer(num(raw$bibd_participant_index)),
  session_ai_condition   = toupper(trimws(raw$session_ai_condition)),
  stringsAsFactors = FALSE)

# demographics
wide$age <- trimws(raw$age)
wide$age_num <- unname(AGE_MIDPOINTS[wide$age])
for (v in names(DEMO_TRANSLATE)) wide[[v]] <- translate(raw[[v]], DEMO_TRANSLATE[[v]])
wide$education <- gsub("’", "'", wide$education)
wide$investment_exp  <- ifelse(toupper(trimws(raw$investment_exp)) == "YES", "Yes", "No")
wide$years_investing <- ifelse(wide$investment_exp == "Yes", num(raw$years_investing), NA_real_)
wide$age_grp         <- ifelse(wide$age %in% c("45-54", "55-64", "65+"), "45+", wide$age)
wide$education_grp   <- ifelse(wide$education %in% c("High school", "Bachelor's"), "High school or Bachelor's", wide$education)
wide$nationality_grp <- ifelse(wide$nationality == "Armenian", "Armenian", "Other")

# self-reports (1-5; confidence 0-5); AI attitude ratings of 0 = not rated
for (v in LIKERT_COLS) wide[[v]] <- parse_likert(raw[[v]])
for (v in AI_ATTITUDE_COLS) {
  wide[[v]][wide[[v]] %in% 0] <- NA
  wide[[v]][wide$session_ai_condition == "NO_AI"] <- NA
}

# decisions: baseline round and five experimental rounds;
# a timer-expired Time Limit round (NO_RESPONSE) is recorded as Hold
wide$baseline_action <- toupper(trimws(raw$task_action))
for (r in ROUNDS) {
  a <- toupper(trimws(raw[[paste0("round", r, "_action")]])); a[is_blank(a)] <- NA
  wide[[paste0("round", r, "_experiment")]] <- trimws(raw[[paste0("round", r, "_experiment")]])
  wide[[paste0("round", r, "_timed_out")]]  <- a %in% "NO_RESPONSE"
  a[a %in% "NO_RESPONSE"] <- "HOLD"
  wide[[paste0("round", r, "_action")]] <- a
}

## ---- timing and assistant use -------------------------------------------------
wide$completed <- !is_blank(raw$end_time) | !is_blank(raw$submit_click_time)
wide$completion_time_min <- secs(raw$end_time, raw$start_time) / 60
wide$baseline_sec <- secs(raw$task_time, raw$next4_click_time)
entry <- c("baseline_click_time", "next_r1_click_time", "next_att_click_time",
           "next_r3_click_time", "next_price_click_time")            # screen entry before rounds 1-5
for (r in ROUNDS) wide[[paste0("round", r, "_sec")]] <- secs(raw[[paste0("round", r, "_time")]], raw[[entry[r]]])
wide$min_decision_sec <- apply(as.matrix(wide[paste0("round", ROUNDS, "_sec")]), 1,
                               function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE))

# messages sent to the AI assistant (counts from the chat logs; see the note above)
for (r in ROUNDS) wide[[paste0("round", r, "_ai_n")]] <- as.integer(num(raw[[paste0("round", r, "_ai_n")]]))
wide$total_ai_requests <- rowSums(wide[paste0("round", ROUNDS, "_ai_n")])
wide$asked_ai   <- wide$total_ai_requests > 0
wide$ai_msg_bad <- as.integer(num(raw$ai_msg_bad))
wide$flag_ai_repeat <- toupper(trimws(raw$ai_msg_repeat)) %in% c("TRUE", "1")

## ---- attention checks and quality score -------------------------------------
wide$probability_check <- num(raw$probability_check)
wide$price_drop        <- num(raw$price_drop)
wide$attn_hold_pass  <- toupper(trimws(raw$attention_action)) %in% ATTN_ANSWERS$attention_action
wide$attn_prob_pass  <- round(wide$probability_check, 4) %in% round(ATTN_ANSWERS$probability_check, 4)
wide$attn_price_pass <- !is.na(wide$price_drop) & abs(wide$price_drop - ATTN_ANSWERS$price_drop) < 1e-6
wide$n_attn_passed   <- wide$attn_hold_pass + wide$attn_prob_pass + wide$attn_price_pass

ct <- wide$completion_time_min
flag_fast <- !is.na(ct) & ct < FAST_THRESHOLD_MIN
flag_slow <- !is.na(ct) & ct > SLOW_THRESHOLD_MIN
q <- stats::quantile(ct[wide$completed], c(.25, .75), na.rm = TRUE, names = FALSE)
flag_outlier  <- !is.na(ct) & (ct < q[1] - 1.5 * diff(q) | ct > q[2] + 1.5 * diff(q))
flag_fast_dec <- !is.na(wide$min_decision_sec) & wide$min_decision_sec < FAST_DECISION_SEC
straight <- apply(as.matrix(wide[LIKERT_COLS]), 1, function(x) { x <- x[!is.na(x)]; length(x) >= 2 && stats::var(x) == 0 })
bad_ratio <- ifelse(wide$total_ai_requests > 0, wide$ai_msg_bad / wide$total_ai_requests, 0)
bad_ratio <- pmax(bad_ratio, ifelse(wide$flag_ai_repeat, 0.5, 0))

s_attn <- wide$n_attn_passed / 3
s_time <- ifelse(flag_fast | flag_slow | flag_outlier | flag_fast_dec, 0, 1)
s_line <- ifelse(straight, 0, 1)
s_ai   <- ifelse(wide$asked_ai, pmax(0, 1 - bad_ratio), 1)
wide$quality_score <- round(100 * (QSCORE_WEIGHTS[["attention"]] * s_attn + QSCORE_WEIGHTS[["comp_time"]] * s_time +
                                   QSCORE_WEIGHTS[["straightline"]] * s_line + QSCORE_WEIGHTS[["ai_chat"]] * s_ai), 1)

## ---- one row per experimental round -----------------------------------------
long <- do.call(rbind, lapply(ROUNDS, function(r) data.frame(
  participant_id = wide$participant_id, round = r,
  experiment     = wide[[paste0("round", r, "_experiment")]],
  action         = wide[[paste0("round", r, "_action")]],
  timed_out      = wide[[paste0("round", r, "_timed_out")]],
  asked_ai_round = wide[[paste0("round", r, "_ai_n")]] > 0,
  decision_sec   = wide[[paste0("round", r, "_sec")]],
  stringsAsFactors = FALSE)))
long <- long[!is.na(long$action), , drop = FALSE]                # rounds not reached are dropped
long$condition <- unname(EXP_TO_CONDITION[long$experiment])
long$target    <- unname(NUDGE_TARGET[long$experiment])
long$on_target <- hits_target(long$action, long$target)
pers <- wide[, c("participant_id", "session_ai_condition", "baseline_action")]
names(pers)[2] <- "ai_condition"
long <- merge(long, pers, by = "participant_id", all.x = TRUE)
long <- long[order(long$participant_id, long$round), ]; rownames(long) <- NULL
long$ai_condition <- stats::relevel(factor(long$ai_condition), ref = "NO_AI")
long$condition    <- factor(long$condition)
long$experiment   <- factor(long$experiment)

## ---- checks and save ----------------------------------------------------------
stopifnot(!anyDuplicated(wide$participant_id), !anyDuplicated(wide$bibd_participant_index),
          all(wide$session_ai_condition %in% c("NO_AI", "NEUTRAL_AI", "BIASED_AI", "DEBIASED_AI")),
          all(wide$baseline_action %in% c("BUY", "HOLD", "SELL")),
          all(long$action %in% c("BUY", "HOLD", "SELL")),
          all(!is.na(long$condition)))
save(wide, long, file = OUT_FILE)
message(sprintf("Saved %s: %d participants, %d experimental rounds", OUT_FILE, nrow(wide), nrow(long)))
