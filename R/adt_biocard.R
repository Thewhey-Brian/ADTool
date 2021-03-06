#' Import BIOCARD Data
#'
#' Import BIOCARD data from source files and generate the analysis dataset.
#'
#' @inheritParams parameters
#'
#' @return
#'
#' Returned the analysis dataset with: patients' ids, baseline times,
#' corresponding biomarkers, biomarker test times, etc.
#'
#' @examples
#' \dontrun{
#' ## with default unoverlaped window
#' dt_biocard <- get_biocard(path, merge_by = "diagnosis")
#'
#' ## with costomized window
#' dt_biocard <- get_biocard(path, merge_by = "diagnosis",
#'                           window = 365,
#'                           window_overlap = TRUE)
#'
#' ## with dictionary provided by user
#' dt_biocard <- get_biocard(path, merge_by = "dx",
#'                           src_tables = "dict_src_tables.xlsx")
#' }
#'
#' @export
#'
#'
adt_get_biocard <- function(path     = ".",
                            merge_by = c("cognitive", "diagnosis", "csf",
                                         "hippocampus", "amygdala",
                                         "entorhinal"),
                            window  = 730, window_overlap = FALSE,
                            pattern    = "*.xls",
                            src_files  = NULL,
                            src_tables = NULL,
                            par_apoe = list(levels = c(3.4, 4.4, 2.4),
                                            labels = c(1, 2, NA)),
                            verbose    = TRUE) {

    ## --------- internal functions -------------------------------------
    ## convert date
    f_date <- function(code, date_name, dta) {
        mvar <- a_map_var("BIOCARD", code, date_name, dict_src_tables)
        dfmt <- dict_src_files %>%
            filter(adt_table_code == code)

        stopifnot(1 == nrow(dfmt))

        dta %>%
            mutate(!!date_name :=
                       as.Date(!!as.name(mvar),
                               dfmt[["src_date_format"]])) %>%
            select(- all_of(mvar))
    }

    ## map var
    f_map <- function(code, var, dta, fc = NULL) {
        mvar <- a_map_var("BIOCARD", code, var, dict_src_tables)
        dta  <- dta %>%
            rename(!!var := mvar)

        if (!is.null(fc))
            dta[var] <- lapply(dta[var], fc)

        dta
    }

    ## --------- prepare pars -------------------------------------

    ## source data set of dates for combining data
    merge_by <- match.arg(merge_by)

    ## switch
    merge_code <- switch(merge_by,
                       diagnosis   = "diag",
                       cognitive   = "cog",
                       csf         = "csf",
                       hippocampus = "hippo",
                       amydata     = "amy",
                       entorhinal   = "ec")

    ## --------- prepare files  -------------------------------------

    ## list all file names matching the pattern
    file_names <- list.files(path       = path,
                             pattern    = pattern,
                             full.names = TRUE)

    ## dictionary of src files
    dict_src_files  <- adt_get_dict("src_files",  csv_fname = src_files)
    dict_src_tables <- adt_get_dict("src_tables", csv_fname = src_tables)
    dict_data       <- adt_get_dict("ana_data")

    ## --------- read tables -------------------------------------
    vec_tbls <- c("COG", "DIAG", "CSF", "DEMO",
                  "HIPPO", "AMY", "EC", "GE")

    chk_all <- NULL
    for (i in vec_tbls) {
        cur_dat  <- a_read_file(i, file_names, dict_src_files, verbose)
        cur_chk  <- a_check_src(i, cur_dat,    dict_src_tables)

        assign(paste("dat_", tolower(i), sep = ""),
               cur_dat)

        chk_all <- rbind(chk_all, cur_chk)
    }

    if (dim(chk_all)[1] > 0) {
        err_msg <- a_err_msg("biocard_load_error")
        message(err_msg)
        print(chk_all)
    }

    dat_lsta  <- a_read_file("LIST_A", file_names, dict_src_files, verbose)
    dat_lstb  <- a_read_file("LIST_B", file_names, dict_src_files, verbose)


    ## ----------  manipulation ----------------------------------
    a_print("Formatting data ...", verbose)

    dat_cog   <- f_date("COG",  "date_cog",   dat_cog)
    dat_cog   <- f_map("COG",   "subject_id", dat_cog)

    dat_diag  <- f_date("DIAG", "date_diag",  dat_diag)
    dat_diag  <- f_map("DIAG",  "subject_id", dat_diag)

    dat_csf   <- f_date("CSF",  "date_csf",   dat_csf)
    dat_csf   <- f_map("CSF",   "abeta",      dat_csf)
    dat_csf   <- f_map("CSF",   "subject_id", dat_csf)

    dat_demo  <- f_map("DEMO", "subject_id", dat_demo)
    dat_demo  <- dat_demo %>%
        select(-c("jhuanonid", "lettercode", "nihid"))

    dat_hippo <- f_date("HIPPO", "date_hippo", dat_hippo)
    dat_hippo <- f_map("HIPPO",  "subject_id", dat_hippo)

    dat_hippo <- f_map("HIPPO",  "intracranial_vol_hippo",
                       dat_hippo, as.numeric)

    dat_hippo <- f_map("HIPPO",  "l_hippo", dat_hippo, as.numeric)
    dat_hippo <- f_map("HIPPO",  "r_hippo", dat_hippo, as.numeric)

    ## MRI amygdala
    dat_amy <- f_date("AMY", "date_amy",        dat_amy)
    dat_amy <- f_map("AMY", "subject_id",       dat_amy)

    dat_amy <- f_map("AMY", "intracranial_vol_amy",
                     dat_amy, as.numeric)

    dat_amy <- f_map("AMY", "l_amy", dat_amy, as.numeric)
    dat_amy <- f_map("AMY", "r_amy", dat_amy, as.numeric)


    ## MRI EC volume
    dat_ec  <- f_date("EC", "date_ec",         dat_ec)
    dat_ec  <- f_map("EC", "subject_id",       dat_ec)
    dat_ec  <- f_map("EC", "intracranial_vol_ec", dat_ec, as.numeric)
    dat_ec  <- f_map("EC", "l_ec_vol",         dat_ec, as.numeric)
    dat_ec  <- f_map("EC", "r_ec_vol",         dat_ec, as.numeric)
    dat_ec  <- f_map("EC", "l_ec_thick",       dat_ec, as.numeric)
    dat_ec  <- f_map("EC", "r_ec_thick",       dat_ec, as.numeric)

    ## process data
    dat_hippo$bi_hippo <- (dat_hippo$l_hippo + dat_hippo$r_hippo) / 2
    dat_amy$bi_amy     <- (dat_amy$l_amy     + dat_amy$r_amy)     / 2
    dat_ec$bi_ec_vol   <- (dat_ec$l_ec_vol   + dat_ec$r_ec_vol)   / 2
    dat_ec$bi_ec_thick <- (dat_ec$l_ec_thick + dat_ec$r_ec_thick) / 2

    ## race
    dat_ge <- dat_ge %>%
        select(-c("jhuanonid", "lettercode", "nihid"))

    dat_ge <- f_map("GE", "subject_id", dat_ge)

    ## exclude subjects from list A and list B
    id_name <- a_map_var("BIOCARD", "LIST_A", "subject_id", dict_src_tables)

    exid <- c(dat_lsta[[id_name]],
              dat_lstb[[id_name]])

    ## ------------- merge all data -------------------------------------
    #dat_all <- dat_cog %>%
    #    left_join(dat_diag,  by = c("subject_id")) %>%
    #    left_join(dat_amy,   by = c("subject_id")) %>%
    #    left_join(dat_csf,   by = c("subject_id")) %>%
    #    left_join(dat_demo,  by = c("subject_id")) %>%
    #    left_join(dat_ec,    by = c("subject_id")) %>%
    #    left_join(dat_ge,    by = c("subject_id")) %>%
    #    left_join(dat_hippo, by = c("subject_id")) 
    
    ## drop duplicat columns
    #dat_all <- dat_all %>%
        select(!(ends_with(".x") | ends_with(".y")))
    
    #aa <- melt(dat_all, id.vars = "subject_id")
    
    ## ------------- prepare bases of dates -----------------------------
    a_print("Merging analysis dataset...", verbose)
    dat_se <- a_window(dat    = get(paste("dat_", merge_code, sep = "")),
                       v_date = paste("date_", merge_code, sep = ""),
                       window,
                       window_overlap)

    ## ------------- combine data --------------------------------------
    dat_se <- a_match(dat_se, dat_diag,  "date_diag")
    dat_se <- a_match(dat_se, dat_cog,   "date_cog")
    dat_se <- a_match(dat_se, dat_csf,   "date_csf")
    dat_se <- a_match(dat_se, dat_hippo, "date_hippo")
    dat_se <- a_match(dat_se, dat_amy,   "date_amy")
    dat_se <- a_match(dat_se, dat_ec,    "date_ec")

    dat_diag_sub <- dat_diag %>%
        select(c("subject_id", "jhuanonid", "lettercode", "nihid",
                 "visitno", "date_diag"))

    dat_se <- dat_se %>%
        left_join(dat_demo, by = c("subject_id")) %>%
        left_join(dat_ge, by = c("subject_id")) %>%
        select(- c("date", "date_left", "date_right")) %>%
        left_join(dat_diag_sub, by = c("subject_id", "date_diag"))

    ## load ApoE-4
    dat_se$apoe <- adt_apoe(dat_se$apoecode)

    ## drop duplicates
    dat_se <- dat_se %>%
        select(!(ends_with(".x") | ends_with(".y")))

    ## add exid
    dat_se <- dat_se %>%
        rowwise() %>%
        mutate(exclude = subject_id %in% exid)
    
    dat_se <- dat_se %>% 
        mutate(sex_group = recode(sex, '1'='Male','2'='Female')) %>% 
        mutate(age =  startyear - birthyear) %>% 
        mutate(age_group = case_when(age <  10            ~ 'under 10', 
                                     age >= 10 & age < 20 ~ '10-19', 
                                     age >= 20 & age < 30 ~ '20-29', 
                                     age >= 30 & age < 40 ~ '30-39', 
                                     age >= 40 & age < 50 ~ '40-49', 
                                     age >= 50 & age < 60 ~ '50-59', 
                                     age >= 60 & age < 70 ~ '60-69', 
                                     age >= 70 & age < 80 ~ '70-79', 
                                     age >= 80 & age < 90 ~ '80-89', 
                                     age >= 90            ~ 'above 89')) %>% 
        group_by(subject_id) %>% 
        mutate(visit = row_number()) %>% 
        mutate(year = if_else(as.numeric(format(date_cog, '%Y')) - startyear < 0, 
                                       0, as.numeric(format(date_cog, '%Y')) - startyear)) %>% 
        ungroup()

    a_print("Done.", verbose)
    ## return
    rtn <- list(ana_dt = dat_se, 
                dat_ty = "biocard", 
                merge_by = merge_by, 
                window = window, 
                overlap = window_overlap)
    class(rtn) <- "ad_ana_data"
    return(rtn)
}
