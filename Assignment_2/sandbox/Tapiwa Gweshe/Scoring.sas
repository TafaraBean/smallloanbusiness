/*==============================================================
  Adaptive Scoring Script — Tapiwa Gweshe
  Uses only variables common to both the model and the scoring data.
==============================================================*/

/* --- Paths --- */
%let A2_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2;
%let A1_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1;

libname here  "&A2_ROOT./sasdata";
libname model "&A1_ROOT./results/models";

/* === 1) Read coefficients === */
data _coef_raw;
  set model.step_params;
  length Variable $64;
  Variable = upcase(strip(Variable));
  if missing(Estimate) then delete;
run;

/* Extract intercept */
proc sql noprint;
  select coalesce(max(Estimate),0)
    into :b0 trimmed
  from _coef_raw
  where Variable in ('INTERCEPT','_INTERCEPT_','CONSTANT','_CONS_');
quit;
%put NOTE: Intercept (b0) = &b0;

/* === 2) Capture variables present in OOS === */
proc contents data=here.oos_prep out=_oos_cols(keep=name) noprint; run;
data _oos_cols; set _oos_cols; name = upcase(name); run;

/* === 3) Keep only model variables that exist in OOS === */
proc sql;
  create table coef_common as
  select r.*
  from _coef_raw as r
  where upcase(r.Variable) in (select name from _oos_cols);
quit;

/* === 4) Split continuous vs class === */
proc sql;
  /* continuous / binary (no class level) */
  create table cont_betas as
  select upcase(Variable) as var length=64, Estimate
  from coef_common
  where missing(ClassVal0)
    and upcase(Variable) not in ('INTERCEPT','_INTERCEPT_','CONSTANT','_CONS_');

  /* class effects (numeric levels in your step_params) */
  create table class_betas as
  select upcase(Variable) as var length=64, ClassVal0, Estimate
  from coef_common
  where not missing(ClassVal0);
quit;

/* make a clean numeric copy of the class level and drop the name that collides */
data class_betas2;
  set class_betas;                 /* has: var (char), ClassVal0 (num/char), Estimate */
  __levelN = input(vvalue(ClassVal0), best32.);   /* always numeric, safe */
  drop ClassVal0;
run;



/* === 5) Scoring Macro === */
%macro score_one(dsin, dsout);
data &dsout;
  set &dsin;
  length var $64 estimate 8 __levelN 8;
  retain _b0;
  if _N_=1 then _b0 = &b0;

  /* Seed PDV so hash keys/data exist with the right types */
  if 0 then set cont_betas(keep=var estimate)
                 class_betas2(keep=var __levelN estimate);

  /* Continuous terms */
  declare hash hC(dataset:'cont_betas');
  hC.defineKey('var');
  hC.defineData('estimate');
  hC.defineDone();
  declare hiter itC('hC');

  /* Class terms (use __levelN instead of ClassVal0) */
  declare hash hK(dataset:'class_betas2');
  hK.defineKey('var','__levelN');
  hK.defineData('estimate','var','__levelN');
  hK.defineDone();
  declare hiter itK('hK');

  linpred = _b0;

  /* sum beta * value for continuous/binary */
  var=''; estimate=.;
  rc = itC.first();
  do while (rc = 0);
    linpred + estimate * input(vvaluex(var), best32.);
    rc = itC.next();
  end;

  /* add class betas when row's value equals the level */
  var=''; estimate=.; __levelN=.;
  rc = itK.first();
  do while (rc = 0);
    if input(vvaluex(var), best32.) = __levelN then linpred + estimate;
    rc = itK.next();
  end;

  pd_hat = 1 / (1 + exp(-linpred));
run;
%mend;


/* === 6) Apply scoring === */
%score_one(here.oos_prep, here.scored_oos);
%score_one(here.oot_prep, here.scored_oot);

/* === 7) QC summary === */
proc means data=here.scored_oos n min max mean; var linpred pd_hat; run;
proc means data=here.scored_oot n min max mean; var linpred pd_hat; run;
