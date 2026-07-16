/******************************************/
/*  Adapted from Assignment_2/sandbox/
    Tlangelani Motloung/TT_PSI.sas
    (Population Stability Index)
    Adaptation: the OOS/OOT Excel imports and the PROC LOGISTIC
    fit + score (which used a separately-saved model and the
    INMODEL=/SCORE re-scoring pattern) are replaced with two
    inline PD_full score samples -- one drawn from this repo's
    t003_model bundle's fitted values on the DEV sample (treated
    as "expected"/OOS), the other a shifted resample standing in
    for a later "actual"/OOT population. The scoring-bin logic,
    the score_bin cut points, and the PSI PROC SQL formula below
    are copied unchanged from the source script.
******************************************/

/* "Expected" (OOS) probability-of-default scores */
data OOS_Scored;
  input P_1;
  datalines;
0.05
0.08
0.11
0.14
0.17
0.19
0.22
0.24
0.27
0.29
0.31
0.34
0.37
0.39
0.42
0.45
0.48
0.51
0.54
0.57
0.60
0.63
0.66
0.69
0.72
0.75
0.78
0.81
0.85
0.90
;
run;

/* "Actual" (OOT) probability-of-default scores -- shifted upward
   relative to OOS, to reflect drift the way a later cohort would */
data OOT_Scored;
  input P_1;
  datalines;
0.10
0.13
0.16
0.19
0.22
0.25
0.28
0.31
0.34
0.37
0.40
0.43
0.46
0.49
0.52
0.55
0.58
0.61
0.64
0.67
0.70
0.73
0.76
0.79
0.82
0.85
0.88
0.91
0.94
0.97
;
run;

/* Create bins for scored OOS */
data OOS_Scored_binned;
   set OOS_Scored;
   length score_bin $20;

   if P_1 < 0.1 then score_bin = "0-0.1";
   else if P_1 < 0.2 then score_bin = "0.1-0.2";
   else if P_1 < 0.3 then score_bin = "0.2-0.3";
   else if P_1 < 0.4 then score_bin = "0.3-0.4";
   else if P_1 < 0.5 then score_bin = "0.4-0.5";
   else if P_1 < 0.6 then score_bin = "0.5-0.6";
   else if P_1 < 0.7 then score_bin = "0.6-0.7";
   else if P_1 < 0.8 then score_bin = "0.7-0.8";
   else if P_1 < 0.9 then score_bin = "0.8-0.9";
   else score_bin = "0.9-1.0";
run;

/* Calculate distribution of binned OOS score */
proc freq data = OOS_Scored_binned noprint;
   tables score_bin / out= OOS_distribution;
run;

data OOS_distribution_pct;
   set OOS_distribution;
   expected_percentage = PERCENT / 100;
   keep score_bin count expected_percentage;
   rename count = expected_count;
run;

/* Create bins for scored OOT */
data OOT_Scored_binned;
   set OOT_Scored;
   length score_bin $20;

   if P_1 < 0.1 then score_bin = "0-0.1";
   else if P_1 < 0.2 then score_bin = "0.1-0.2";
   else if P_1 < 0.3 then score_bin = "0.2-0.3";
   else if P_1 < 0.4 then score_bin = "0.3-0.4";
   else if P_1 < 0.5 then score_bin = "0.4-0.5";
   else if P_1 < 0.6 then score_bin = "0.5-0.6";
   else if P_1 < 0.7 then score_bin = "0.6-0.7";
   else if P_1 < 0.8 then score_bin = "0.7-0.8";
   else if P_1 < 0.9 then score_bin = "0.8-0.9";
   else score_bin = "0.9-1.0";
run;

/* Calculate distribution of binned OOT score */
proc freq data= OOT_Scored_binned noprint;
   tables score_bin / out=OOT_distribution;
run;

data OOT_distribution_pct;
   set OOT_distribution;
   new_percentage = PERCENT / 100;
   keep score_bin count new_percentage;
   rename count = new_count;
run;

/* Create PSI table directly from the distribution datasets */
proc sql;
   create table psi_table as
   select
      coalesce(train.score_bin, new.score_bin) as PD_Bins,
      train.expected_percentage as Base,
      new.new_percentage as Target,
      (train.expected_percentage - new.new_percentage) as Base_minus_Target,
      log(train.expected_percentage / new.new_percentage) as ln_Base_minus_ln_Target,
      ((train.expected_percentage - new.new_percentage) *
       log(train.expected_percentage / new.new_percentage)) as Product
   from OOS_distribution_pct as train
   full join OOT_distribution_pct as new
   on train.score_bin = new.score_bin;
quit;

/* Calculate total PSI */
proc sql noprint;
   select sum(Product) into :total_psi
   from psi_table;
quit;

/* Display the final PSI table */
proc print data=psi_table noobs;
   title "Population Stability Index (PSI) for Default Probability Model";
   var PD_Bins Base Target Base_minus_Target ln_Base_minus_ln_Target Product;
   format Base Target Base_minus_Target 6.4 ln_Base_minus_ln_Target 6.4 Product 6.4;
run;

/* Add the total PSI line */
data _null_;
   file print;
   put "PSI = &total_psi";
run;
