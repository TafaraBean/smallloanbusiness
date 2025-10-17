/**************************************************************/
/*   SCORING (Viya for Learners): Train + Score + Full Outputs */
/**************************************************************/

options mprint mlogic symbolgen;

/* --------- Paths / Libs --------- */
%let A2_ROOT = /export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2;
%let DEV_XLS = &A2_ROOT./data/raw/SmallBusinessLoans.xlsx;

%macro ensure_lib(lib, path);
  %if %sysfunc(libref(&lib)) %then %do; libname &lib "&path"; %end;
%mend;
%ensure_lib(here, &A2_ROOT./sasdata)
%ensure_lib(out,  &A2_ROOT./output/tables)

/* --- Viya-safe Results setup --- */
ods results on;
ods _all_ close;

ods html5 (id=web)
    style=HTMLBlue
    options(bitmap_mode='inline' svg_mode='none')
    newfile=none;   /* optional; keeps it to one HTML file */

ods graphics / reset imagename="fig" imagefmt=png width=900px height=550px;

/* ============================================================
   0 - Import DEV (Excel) & Clean to match modeling rules
   ============================================================ */
filename file_dev "&DEV_XLS";
proc import datafile=file_dev dbms=xlsx out=dev_raw replace;
  getnames=yes;
run;

data loans_clean;
  set dev_raw;

  /* Robust recode of RevLineCr -> numeric {0,1} */
  length _rlc $1;
  _rlc = strip(upcase(vvaluex('RevLineCr')));
  if _rlc in ('Y','T','1') then RevLineCr_num=1; else RevLineCr_num=0;
  drop RevLineCr; rename RevLineCr_num=RevLineCr;

  /* FranchiseCode binarize */
  if FranchiseCode <= 1 then FranchiseCode = 0; else FranchiseCode = 1;

  /* Drop identifiers / non-predictors */
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;

  /* Default to in-sample if missing */
  if missing(Selected) then Selected=1;
run;

/* ============================================================
   1 - Train logistic on DEV (show fit stats + ROC)
   ============================================================ */
title "DEV: Logistic Model (Stepwise)";
proc logistic data=loans_clean(where=(Selected=1))
              outmodel=out.logistic_model
              plots(only)=roc(id=prob);
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default(event='1') =
        Term NoEmp CreateJob RetainedJob FranchiseCode
        UrbanRural RevLineCr DisbursementGross RealEstate
        Portion Recession
        / selection=stepwise slentry=0.05 slstay=0.05
          lackfit stb;
  ods output Association=out.dev_ROCassoc
             ROCCurve   =out.dev_ROCcurve
             ParameterEstimates=out.dev_Params
             LackFitPartition=out.dev_HL;
run;

/* Quick view of key DEV tables */
title "DEV: AUC and ROC Association"; proc print data=out.dev_ROCassoc noobs; run;
title "DEV: First 10 ROC Curve Points"; proc print data=out.dev_ROCcurve(obs=10) noobs; run;
title "DEV: Parameter Estimates"; proc print data=out.dev_Params noobs; run;
title "DEV: Hosmer-Lemeshow Partition"; proc print data=out.dev_HL noobs; run;

/* ============================================================
   2 - Score prepared OOS & OOT
   ============================================================ */
proc logistic inmodel=out.logistic_model;
  score data=here.oos_prep out=out.oos_scored;  
run;

proc logistic inmodel=out.logistic_model;
  score data=here.oot_prep out=out.oot_scored;
run;

/* Post-process: add pd_hat and linpred (clipped logit) */
%let _eps=1e-8;

data out.oos_scored_pp;
  set out.oos_scored;
  pd_hat = P_1;
  _p = min(max(pd_hat,&_eps),1-&_eps);
  linpred = log(_p/(1-_p));
  drop _p;
run;

data out.oot_scored_pp;
  set out.oot_scored;
  pd_hat = P_1;
  _p = min(max(pd_hat,&_eps),1-&_eps);
  linpred = log(_p/(1-_p));
  drop _p;
run;

/* ============================================================
   3) Utility Macros (Brier, Deciles, ROC-from-scores, KS/Lift, PSI)
   ============================================================ */

/* Variable detection */
%macro has_var(ds, var);
  %local dsid pos rc; %let dsid=%sysfunc(open(&ds,i));
  %if &dsid %then %do; %let pos=%sysfunc(varnum(&dsid,&var)); %let rc=%sysfunc(close(&dsid)); &pos %end;
  %else 0
%mend;

/* Brier score */
%macro brier(ds, y=bad_flag, out=, label=);
  %if %has_var(&ds,&y) > 0 %then %do;
    proc sql noprint;
      create table &out as
      select mean((pd_hat - &y)**2) as Brier format=8.6 from &ds;
    quit;
    title "Brier Score — &label"; proc print data=&out noobs; run;
  %end;
%mend;

/* Deciles: table + overlay plot */
%macro deciles(ds, y=bad_flag, out=, label=);
  %if %has_var(&ds,&y) > 0 %then %do;
    proc rank data=&ds groups=10 out=__r descending;
      var pd_hat; ranks dec;
    run;
    proc sql;
      create table &out as
      select (dec+1) as decile,
             count(*) as n,
             mean(pd_hat) as avg_pd format=8.4,
             mean(&y)     as bad_rate format=8.4
      from __r group by dec order by dec;
    quit;
    title "Deciles — &label (avg_pd vs bad_rate)";
    proc print data=&out noobs; run;

    title "Deciles Plot — &label";
    proc sgplot data=&out;
      series x=decile y=avg_pd   / markers lineattrs=(thickness=2);
      series x=decile y=bad_rate / markers lineattrs=(pattern=shortdash thickness=2);
      yaxis label="Rate"; xaxis integer label="Decile (1 = highest PD)";
      keylegend / position=topright across=1;
    run;

    proc datasets lib=work nolist; delete __r; quit;
  %end;
%mend;

/* ROC/AUC from scored data, KS & Gains/Lift */
%macro roc_ks_lift(ds, y=bad_flag, label=, prefix=);
  %if %has_var(&ds,&y) > 0 %then %do;
    proc logistic data=&ds;
      model &y(event='1') = ;
      roc "&label" pred=pd_hat;
      ods output ROCAssociation=out.&prefix._ROCassoc
                 ROCcurve      =out.&prefix._ROCcurve;
    run;

    title "&label: AUC / ROC Association";
    proc print data=out.&prefix._ROCassoc noobs; run;

    title "&label: ROC Curve";
    proc sgplot data=out.&prefix._ROCcurve;
      series x=_1MSPEC_ y=_SENSIT_ / markers;
      lineparm x=0 y=0 slope=1 / transparency=0.7;
      xaxis label="1 - Specificity"; yaxis label="Sensitivity";
    run;

    proc rank data=&ds groups=10 out=__ks descending; var pd_hat; ranks dec; run;

    proc sql noprint;
      select sum(&y), sum(1-&y), count(*)
        into :TOT_BADS, :TOT_GOODS, :TOT_N
      from &ds;
    quit;

    proc sql;
      create table out.&prefix._decroll as
      select (dec+1) as decile,
             count(*)    as n,
             sum(&y)     as bads,
             sum(1-&y)   as goods,
             mean(pd_hat) as avg_pd
      from __ks group by dec order by dec;
    quit;

    data out.&prefix._decroll;
      set out.&prefix._decroll end=last;
      retain cum_n cum_bads cum_goods 0;
      cum_n     + n;
      cum_bads  + bads;
      cum_goods + goods;

      length _tot_bads _tot_goods _tot_n 8;
      _tot_bads  = max(&TOT_BADS, 0);
      _tot_goods = max(&TOT_GOODS,0);
      _tot_n     = max(&TOT_N,     1);

      if _tot_bads  > 0 then cum_bad_rate  = cum_bads  / _tot_bads;  else cum_bad_rate  = .;
      if _tot_goods > 0 then cum_good_rate = cum_goods / _tot_goods; else cum_good_rate = .;
      if _tot_bads  > 0 then cum_capture   = cum_bads  / _tot_bads;  else cum_capture   = .;

      if cum_n > 0 then lift = cum_capture / (cum_n / _tot_n); else lift = .;

      ks = abs(sum(cum_bad_rate, -cum_good_rate));
      drop _tot_bads _tot_goods _tot_n;
    run;

    proc sql noprint;
      create table out.&prefix._KS as
      select decile, ks format=8.4
      from out.&prefix._decroll
      having ks = max(ks);
    quit;

    title "&label: KS by Decile (max)";
    proc print data=out.&prefix._KS noobs; run;

    title "&label: Gains / Lift Chart";
    proc sgplot data=out.&prefix._decroll;
      series x=decile y=cum_capture / markers;
      series x=decile y=lift        / y2axis markers;
      xaxis integer label="Decile (1 = highest PD)";
      yaxis label="Cumulative Capture (Bad %)"; y2axis label="Lift";
      keylegend / position=topright;
    run;

    proc datasets lib=work nolist; delete __ks; quit;
  %end;
%mend;

/* ==== PSI on pd_hat (OOS expected vs OOT actual) ==== */
%macro psi_pd(expected_ds, actual_ds, score=pd_hat, out=out.psi_pd, label=PSI);
  %local _eps NEXP NACT;
  %let _eps = 1e-8;
  options nosyntaxcheck;

  data __bins; do bin=0 to 9; output; end; run;

  data __exp; set &expected_ds(keep=&score);
    length bin 8;
    s=&score; if s<0 then s=0; else if s>1 then s=1;
    bin=floor(s*10); if bin=10 then bin=9;
  run;

  proc sql;
    create table __exp_cnt as select bin, count(*) as n_exp from __exp group by bin;
    create table __exp_cnt2 as
      select b.bin, coalesce(c.n_exp,0) as n_exp
      from __bins b left join __exp_cnt c on b.bin=c.bin
      order by b.bin;
  quit;

  proc sql noprint; select sum(n_exp) into :NEXP from __exp_cnt2; quit;
  data __exp_pct; set __exp_cnt2; p_exp = n_exp / max(&NEXP,1); run;

  data __act; set &actual_ds(keep=&score);
    length bin 8;
    s=&score; if s<0 then s=0; else if s>1 then s=1;
    bin=floor(s*10); if bin=10 then bin=9;
  run;

  proc sql;
    create table __act_cnt as select bin, count(*) as n_act from __act group by bin;
    create table __act_cnt2 as
      select b.bin, coalesce(c.n_act,0) as n_act
      from __bins b left join __act_cnt c on b.bin=c.bin
      order by b.bin;
  quit;

  proc sql noprint; select sum(n_act) into :NACT from __act_cnt2; quit;
  data __act_pct; set __act_cnt2; p_act = n_act / max(&NACT,1); run;

  proc sql;
    create table &out as
    select coalesce(e.bin,a.bin) as PD_Bins,
           coalesce(e.p_exp,0)   as Base,
           coalesce(a.p_act,0)   as Target,
           (calculated Base - calculated Target) as Base_minus_Target,
           log(max(&&_eps,calculated Base))
            - log(max(&&_eps,calculated Target))  as ln_Base_minus_ln_Target,
           (calculated Base_minus_Target)
            * (calculated ln_Base_minus_ln_Target) as Product
    from __exp_pct e
    full join __act_pct a
      on e.bin=a.bin
    order by PD_Bins;
  quit;

  proc sql noprint; select sum(Product) into :total_psi from &out; quit;

  title "Population Stability Index (PSI) — &label";
  proc print data=&out noobs label;
    var PD_Bins Base Target Base_minus_Target ln_Base_minus_ln_Target Product;
    format Base Target Base_minus_Target ln_Base_minus_ln_Target 6.4 Product 6.4;
  run;

  data _null_; file print; put "PSI = &total_psi"; run;

  proc datasets lib=work nolist;
    delete __bins __exp __act __exp_cnt __act_cnt __exp_cnt2 __act_cnt2 __exp_pct __act_pct;
  quit; title;
%mend;

/* ============================================================
   4) OOS — metrics, plots, ROC, KS/Lift
   ============================================================ */
title "OOS: Summary Stats (pd_hat, linpred)";
proc means data=out.oos_scored_pp n mean std min p25 p50 p75 max;
  var pd_hat linpred;
run;

title "OOS: Histogram of pd_hat";
proc sgplot data=out.oos_scored_pp;
  histogram pd_hat; density pd_hat;
  xaxis label="pd_hat"; yaxis label="Frequency";
run;

%brier (out.oos_scored_pp, y=bad_flag, out=out.oos_Brier, label=OOS);
%deciles(out.oos_scored_pp, y=bad_flag, out=out.oos_deciles, label=OOS);
%roc_ks_lift(out.oos_scored_pp, y=bad_flag, label=OOS, prefix=oos);

/* ============================================================
   5) OOT — metrics, plots, ROC, KS/Lift
   ============================================================ */
title "OOT: Summary Stats (pd_hat, linpred)";
proc means data=out.oot_scored_pp n mean std min p25 p50 p75 max;
  var pd_hat linpred;
run;

title "OOT: Histogram of pd_hat";
proc sgplot data=out.oot_scored_pp;
  histogram pd_hat; density pd_hat;
  xaxis label="pd_hat"; yaxis label="Frequency";
run;

%brier (out.oot_scored_pp, y=bad_flag, out=out.oot_Brier, label=OOT);
%deciles(out.oot_scored_pp, y=bad_flag, out=out.oot_deciles, label=OOT);
%roc_ks_lift(out.oot_scored_pp, y=bad_flag, label=OOT, prefix=oot);

/* ============================================================
   6) PSI on pd_hat (OOS expected vs OOT actual)
   ============================================================ */
%psi_pd(out.oos_scored_pp, out.oot_scored_pp, score=pd_hat, out=out.psi_pd_hat,
        label=OOS (expected) vs OOT (actual));

title; footnote;
/* --------- END --------- */

/* ===========================
   EXPORT ALL ARTIFACTS TO DISK
   =========================== */

/* Where to write exports */
%let EXPDIR=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2/sandbox/Tapiwa Gweshe;

/* Make a subfolder for plots (OK if it already exists) */
options dlcreatedir;
libname _plots "&EXPDIR./plots";
libname _plots clear;

/* ---------- 1) Save plots as PNG ---------- */
/* In Viya, images are written when LISTING is open and GPATH is set */
ods listing gpath="&EXPDIR./plots";
ods graphics on / reset noborder imagefmt=png width=1100px height=700px;

/* Re-draw each figure with explicit file names so you get standalone PNGs */

/* DEV ROC from training */
ods graphics / imagename="dev_roc_curve";
proc sgplot data=out.dev_ROCcurve;
  series x=_1MSPEC_ y=_SENSIT_ / markers;
  lineparm x=0 y=0 slope=1 / transparency=0.7;
  xaxis label="1 - Specificity"; yaxis label="Sensitivity";
  title "DEV: ROC Curve";
run;

/* OOS histogram */
ods graphics / imagename="oos_hist_pd_hat";
proc sgplot data=out.oos_scored_pp;
  histogram pd_hat; density pd_hat;
  xaxis label="pd_hat"; yaxis label="Frequency";
  title "OOS: Histogram of pd_hat";
run;

/* OOS deciles overlay */
ods graphics / imagename="oos_deciles_overlay";
proc sgplot data=out.oos_deciles;
  series x=decile y=avg_pd   / markers lineattrs=(thickness=2);
  series x=decile y=bad_rate / markers lineattrs=(pattern=shortdash thickness=2);
  xaxis integer label="Decile (1 = highest PD)"; yaxis label="Rate";
  keylegend / position=topright;
  title "OOS: Deciles (avg_pd vs bad_rate)";
run;

/* OOS ROC curve (from scored data) */
ods graphics / imagename="oos_roc_curve";
proc sgplot data=out.oos_ROCcurve;
  series x=_1MSPEC_ y=_SENSIT_ / markers;
  lineparm x=0 y=0 slope=1 / transparency=0.7;
  xaxis label="1 - Specificity"; yaxis label="Sensitivity";
  title "OOS: ROC Curve";
run;

/* OOS gains/lift */
ods graphics / imagename="oos_gains_lift";
proc sgplot data=out.oos_decroll;
  series x=decile y=cum_capture / markers;
  series x=decile y=lift / y2axis markers;
  xaxis integer label="Decile (1 = highest PD)";
  yaxis label="Cumulative Capture (Bad %)"; y2axis label="Lift";
  keylegend / position=topright;
  title "OOS: Gains / Lift";
run;

/* OOT histogram */
ods graphics / imagename="oot_hist_pd_hat";
proc sgplot data=out.oot_scored_pp;
  histogram pd_hat; density pd_hat;
  xaxis label="pd_hat"; yaxis label="Frequency";
  title "OOT: Histogram of pd_hat";
run;

/* OOT deciles overlay */
ods graphics / imagename="oot_deciles_overlay";
proc sgplot data=out.oot_deciles;
  series x=decile y=avg_pd   / markers lineattrs=(thickness=2);
  series x=decile y=bad_rate / markers lineattrs=(pattern=shortdash thickness=2);
  xaxis integer label="Decile (1 = highest PD)"; yaxis label="Rate";
  keylegend / position=topright;
  title "OOT: Deciles (avg_pd vs bad_rate)";
run;

/* OOT ROC curve */
ods graphics / imagename="oot_roc_curve";
proc sgplot data=out.oot_ROCcurve;
  series x=_1MSPEC_ y=_SENSIT_ / markers;
  lineparm x=0 y=0 slope=1 / transparency=0.7;
  xaxis label="1 - Specificity"; yaxis label="Sensitivity";
  title "OOT: ROC Curve";
run;

/* OOT gains/lift */
ods graphics / imagename="oot_gains_lift";
proc sgplot data=out.oot_decroll;
  series x=decile y=cum_capture / markers;
  series x=decile y=lift / y2axis markers;
  xaxis integer label="Decile (1 = highest PD)";
  yaxis label="Cumulative Capture (Bad %)"; y2axis label="Lift";
  keylegend / position=topright;
  title "OOT: Gains / Lift";
run;

/* Ensure &total_psi exists and is numeric */
%global total_psi;

%if %sysevalf(%superq(total_psi)=,boolean) %then %do;
  /* Recompute from the PSI table if the macro var isn't set */
  proc sql noprint;
    select coalesce(sum(Product), .)
    into :total_psi trimmed
    from out.psi_pd_hat;
  quit;
%end;


/* ---------- 2) Create a one-row table with PSI value ---------- */
data out.psi_value;
  length Metric $32 Value 8.;
  Metric="PSI (OOS vs OOT)"; Value=&total_psi;
run;

/* ---------- 3) Write a single Excel workbook with all tables ---------- */
ods excel file="&EXPDIR./Model_Report.xlsx" options(embedded_titles='yes');

ods excel options(sheet_name="DEV_ROC_assoc");
proc print data=out.dev_ROCassoc noobs; title "DEV: AUC / ROC Association"; run;

ods excel options(sheet_name="DEV_ROC_curve (first 10)");
proc print data=out.dev_ROCcurve(obs=10) noobs; title "DEV: ROC Curve Points (first 10)"; run;

ods excel options(sheet_name="DEV_Params");
proc print data=out.dev_Params noobs; title "DEV: Parameter Estimates"; run;

ods excel options(sheet_name="DEV_HL");
proc print data=out.dev_HL noobs; title "DEV: Hosmer–Lemeshow"; run;

ods excel options(sheet_name="OOS_Means");
proc means data=out.oos_scored_pp n mean std min p25 p50 p75 max; var pd_hat linpred; title "OOS: Summary Stats"; run;

ods excel options(sheet_name="OOS_Brier");
proc print data=out.oos_Brier noobs; title "OOS: Brier Score"; run;

ods excel options(sheet_name="OOS_Deciles");
proc print data=out.oos_deciles noobs; title "OOS: Deciles"; run;

ods excel options(sheet_name="OOS_ROC_assoc");
proc print data=out.oos_ROCassoc noobs; title "OOS: ROC Association"; run;

ods excel options(sheet_name="OOS_KS_max");
proc print data=out.oos_KS noobs; title "OOS: KS (max)"; run;

ods excel options(sheet_name="OOS_DecRoll");
proc print data=out.oos_decroll noobs; title "OOS: Decile Rollup (Gains/Lift)"; run;

ods excel options(sheet_name="OOT_Means");
proc means data=out.oot_scored_pp n mean std min p25 p50 p75 max; var pd_hat linpred; title "OOT: Summary Stats"; run;

ods excel options(sheet_name="OOT_Brier");
proc print data=out.oot_Brier noobs; title "OOT: Brier Score"; run;

ods excel options(sheet_name="OOT_Deciles");
proc print data=out.oot_deciles noobs; title "OOT: Deciles"; run;

ods excel options(sheet_name="OOT_ROC_assoc");
proc print data=out.oot_ROCassoc noobs; title "OOT: ROC Association"; run;

ods excel options(sheet_name="OOT_KS_max");
proc print data=out.oot_KS noobs; title "OOT: KS (max)"; run;

ods excel options(sheet_name="OOT_DecRoll");
proc print data=out.oot_decroll noobs; title "OOT: Decile Rollup (Gains/Lift)"; run;

ods excel options(sheet_name="PSI_Table");
proc print data=out.psi_pd_hat noobs label;
  title "PSI Table (OOS expected vs OOT actual)";
run;

ods excel options(sheet_name="PSI_Value");
proc print data=out.psi_value noobs; title "PSI Value"; run;

ods excel close;

/* ---------- 4) Also dump CSV copies of the key tables ---------- */
%macro export_csv(ds);
  proc export data=&ds. outfile="&EXPDIR./%sysfunc(lowcase(%scan(&ds.,2,.))).csv"
    dbms=csv replace; run;
%mend;

%export_csv(out.dev_ROCassoc);
%export_csv(out.dev_ROCcurve);
%export_csv(out.dev_Params);
%export_csv(out.dev_HL);
%export_csv(out.oos_Brier);
%export_csv(out.oos_deciles);
%export_csv(out.oos_ROCassoc);
%export_csv(out.oos_decroll);
%export_csv(out.oos_KS);
%export_csv(out.oot_Brier);
%export_csv(out.oot_deciles);
%export_csv(out.oot_ROCassoc);
%export_csv(out.oot_decroll);
%export_csv(out.oot_KS);
%export_csv(out.psi_pd_hat);
%export_csv(out.psi_value);

/* (Optional) export the scored datasets too */
%export_csv(out.oos_scored_pp);
%export_csv(out.oot_scored_pp);

/* Leave LISTING open until all plots are written */
ods listing close;
/* ========================= End export block ========================= */


/* --- Close Studio destination at the end --- */
ods html5 (id=web) close;
ods listing close;
