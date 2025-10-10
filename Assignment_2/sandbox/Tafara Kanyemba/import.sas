/* ==========================================================
   BWIN621 – Assignment 2 (Role A)
   Basic DEV, OOS & OOT Data Audit + Jobs Created & Retained Plots
   ========================================================== */

/* Step 0: Folder path and library */
%let PROJ_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2;
libname here "&PROJ_ROOT/sasdata";

/* Step 1: Import Excel files */
proc import datafile="&PROJ_ROOT/data/raw/SmallBusinessLoans.xlsx"
    out=here.dev_raw
    dbms=xlsx
    replace;
    getnames=yes;
run;

proc import datafile="&PROJ_ROOT/data/raw/SmallBusinessLoans_OOS.xlsx"
    out=here.oos_raw
    dbms=xlsx
    replace;
    getnames=yes;
run;

proc import datafile="&PROJ_ROOT/data/raw/SmallBusinessLoans_OOT.xlsx"
    out=here.oot_raw
    dbms=xlsx
    replace;
    getnames=yes;
run;

/* Step 2: Create bad_flag (1 = Default, 0 = No Default) */
data here.dev_raw; set here.dev_raw;
    if Default = 1 then bad_flag = 1; else bad_flag = 0;
run;

data here.oos_raw; set here.oos_raw;
    if Default = 1 then bad_flag = 1; else bad_flag = 0;
run;

data here.oot_raw; set here.oot_raw;
    if Default = 1 then bad_flag = 1; else bad_flag = 0;
run;

/* Step 3: Counts and default prevalence for DEV, OOS, and OOT */
proc sql;
    create table work.counts_dev as
    select count(*) as Total_Records,
           mean(bad_flag)*100 as Default_Rate_Percent
    from here.dev_raw;

    create table work.counts_oos as
    select count(*) as Total_Records,
           mean(bad_flag)*100 as Default_Rate_Percent
    from here.oos_raw;

    create table work.counts_oot as
    select count(*) as Total_Records,
           mean(bad_flag)*100 as Default_Rate_Percent
    from here.oot_raw;
quit;

/* Step 4: Export counts to CSV */
proc export data=work.counts_dev
    outfile="&PROJ_ROOT/output/tables/counts_dev.csv"
    dbms=csv
    replace;
run;

proc export data=work.counts_oos
    outfile="&PROJ_ROOT/output/tables/counts_oos.csv"
    dbms=csv
    replace;
run;

proc export data=work.counts_oot
    outfile="&PROJ_ROOT/output/tables/counts_oot.csv"
    dbms=csv
    replace;
run;

/* Step 5: Simple data dictionary (from DEV) */
proc contents data=here.dev_raw out=work.data_dictionary noprint;
run;

data work.data_dictionary_clean;
    set work.data_dictionary;
    if type = 1 then var_type = "Numeric";
    else if type = 2 then var_type = "Character";
    keep name var_type length;
run;

proc export data=work.data_dictionary_clean
    outfile="&PROJ_ROOT/output/tables/data_dictionary.csv"
    dbms=csv
    replace;
run;

/* Step 6: Quick missing-value checks */
proc means data=here.dev_raw n nmiss;
    title "Missing Numeric Values - DEV";
run;

proc freq data=here.dev_raw;
    tables _character_ / missing;
    title "Missing Character Values - DEV";
run;

proc means data=here.oos_raw n nmiss;
    title "Missing Numeric Values - OOS";
run;

proc freq data=here.oos_raw;
    tables _character_ / missing;
    title "Missing Character Values - OOS";
run;

proc means data=here.oot_raw n nmiss;
    title "Missing Numeric Values - OOT";
run;

proc freq data=here.oot_raw;
    tables _character_ / missing;
    title "Missing Character Values - OOT";
run;

title;

/* Step 7: Display counts */
title "DEV Counts and Prevalence";
proc print data=work.counts_dev; run;

title "OOS Counts and Prevalence";
proc print data=work.counts_oos; run;

title "OOT Counts and Prevalence";
proc print data=work.counts_oot; run;

title "Data Dictionary (first 20)";
proc print data=work.data_dictionary_clean(obs=20); run;

title;

/* ==========================================================
   Step 8: Average Jobs Created per dataset (DEV, OOS, OOT)
   ========================================================== */

proc sql;
    create table work.avg_jobs_created as
    select "DEV" as Dataset, mean(CreateJob) as Avg_Jobs_Created
    from here.dev_raw
    union all
    select "OOS", mean(CreateJob)
    from here.oos_raw
    union all
    select "OOT", mean(CreateJob)
    from here.oot_raw;
quit;

/* Display table */
title "Average Jobs Created by Dataset";
proc print data=work.avg_jobs_created noobs;
    format Avg_Jobs_Created 8.2;
run;

/* Bar chart for jobs created */
title "Average Number of Jobs Created by Dataset";
proc sgplot data=work.avg_jobs_created;
    vbar Dataset / response=Avg_Jobs_Created datalabel;
    yaxis label="Average Jobs Created";
    xaxis label="Dataset";
run;

title;

/* ==========================================================
   Step 9: Average Jobs Retained per dataset (DEV, OOS, OOT)
   ========================================================== */

proc sql;
    create table work.avg_jobs_retained as
    select "DEV" as Dataset, mean(RetainedJob) as Avg_Jobs_Retained
    from here.dev_raw
    union all
    select "OOS", mean(RetainedJob)
    from here.oos_raw
    union all
    select "OOT", mean(RetainedJob)
    from here.oot_raw;
quit;

/* Display table */
title "Average Jobs Retained by Dataset";
proc print data=work.avg_jobs_retained noobs;
    format Avg_Jobs_Retained 8.2;
run;

/* Bar chart for jobs retained */
title "Average Number of Jobs Retained by Dataset";
proc sgplot data=work.avg_jobs_retained;
    vbar Dataset / response=Avg_Jobs_Retained datalabel;
    yaxis label="Average Jobs Retained";
    xaxis label="Dataset";
run;

title;
