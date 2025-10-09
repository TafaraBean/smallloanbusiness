/*==============================================================
  SCORING ONLY — uses Assignment_1/results/models/step_params.sas7bdat
  Data to score: Assignment_2/sasdata -> here.oos_prep, here.oot_prep
  Output: here.scored_oos, here.scored_oot (linpred, pd_hat)
==============================================================*/

/* Paths */
%let A2_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2;
%let A1_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1;

libname here  "&A2_ROOT./sasdata";
libname model "&A1_ROOT./results/models";

/* --- Sanity checks --- */
%if ^%sysfunc(exist(here.oos_prep)) %then %do; %put ERROR: here.oos_prep not found.; %abort cancel; %end;
%if ^%sysfunc(exist(here.oot_prep)) %then %do; %put ERROR: here.oot_prep not found.; %abort cancel; %end;
%if ^%sysfunc(exist(model.step_params)) %then %do; %put ERROR: model.step_params not found.; %abort cancel; %end;

/* === 1) Read betas and normalise names === */
data _coef_raw;
  set model.step_params;
  length Variable $64;
  Variable = upcase(strip(Variable));          /* case-insensitive join */
  if missing(Estimate) then delete;
run;

/* Intercept */
proc sql noprint;
  select coalesce(max(Estimate),0)
    into :b0 trimmed
  from _coef_raw
  where Variable in ('INTERCEPT','_INTERCEPT_','CONSTANT','_CONS_');
quit;
%put NOTE: Intercept (b0) = &b0;

/* Columns present in OOS (we’ll use this schema for matching) */
proc contents data=here.oos_prep out=_oos_cols(keep=name) noprint; run;
data _oos_cols; set _oos_cols; name = upcase(name); run;

/* Split into continuous vs class terms and keep only variables that exist in OOS */
/* CLASS terms – rename key column so it can't collide with input tables */
/* === make scoring tables with UNIQUE column names === */
/* class (ensure __levelN is NUMERIC even if ClassVal0 is char) */
/* continuous / binary terms present in OOS */
proc sql;
  create table cont_betas_raw as
  select c.name as var length=64, r.Estimate
  from _oos_cols as c
  join _coef_raw  as r
    on c.name = r.Variable
  where r.Variable not in ('INTERCEPT','_INTERCEPT_','CONSTANT','_CONS_')
    and missing(r.ClassVal0);
quit;

data cont_betas;
  set cont_betas_raw(rename=(var=__keyvar estimate=__beta));
run;

/* Materialize with numeric level */
data class_betas;
  set class_betas_raw(rename=(var=__keyvar estimate=__beta));
  /* vvalue() returns a CHARACTER view of the value irrespective of source type;
     input(..., best32.) converts it to NUMERIC reliably */
  __levelN = input(vvalue(ClassVal0), best32.);
  drop ClassVal0;
run;


/* rename columns so they won't collide with ANYTHING in the input row */
data cont_betas;
  set cont_betas_raw(rename=(var=__keyvar estimate=__beta));
run;

/* === scoring (hash-based, using ONLY the __* names) === */
%macro score_one(dsin, dsout);
data &dsout;
  set &dsin;

  retain _b0; if _n_=1 then _b0=&b0;

  /* Preload metadata FIRST so types are fixed from the lookup tables */
  if 0 then set cont_betas class_betas;

  /* Only declare what isn't coming from the preload */
  length __keyvar $64 __beta 8;

  declare hash hC(dataset:'cont_betas');   hC.defineKey('__keyvar');                hC.defineData('__beta'); hC.defineDone();
  declare hiter itC('hC');

  declare hash hK(dataset:'class_betas');  hK.defineKey('__keyvar','__levelN');     hK.defineData('__beta'); hK.defineDone();
  declare hiter itK('hK');

  linpred = _b0;

  /* continuous */
  rc = itC.first();
  do while (rc = 0);
    linpred + __beta * input(vvaluex(__keyvar), best32.);
    rc = itC.next();
  end;

  /* class */
  rc = itK.first();
  do while (rc = 0);
    if input(vvaluex(__keyvar), best32.) = __levelN then linpred + __beta;
    rc = itK.next();
  end;

  pd_hat = 1/(1+exp(-linpred));
run;
%mend;




/* === 3) Score OOS & OOT === */
%score_one(here.oos_prep, here.scored_oos);
%score_one(here.oot_prep, here.scored_oot);

/* Tiny QC so you see something in Results */
proc sql;
  select "OOS rows" as what, count(*) as n from here.scored_oos
  union all
  select "OOT rows", count(*) from here.scored_oot;
quit;

proc print data=here.scored_oos(obs=10); var linpred pd_hat bad_flag; run;
proc print data=here.scored_oot(obs=10); var linpred pd_hat bad_flag; run;
