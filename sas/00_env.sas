/**************************************************************************
* 00_env.sas — Portable bootstrap for SAS Viya + GitHub repo
* - Auto-detects repo root from the program you run (99_driver.sas or any
*   file under /sas), so users normally change NOTHING.
* - Optional: set &root_override if detection fails.
**************************************************************************/

options dlcreatedir fullstimer;

/* ── Optional manual override (leave blank for auto) ───────────────── */
%let root_override=;   /* e.g. /export/viya/homes/<id>/casuser/BWIN621_Project */

/* ── Derive repo root from the top-level program’s folder (/sas → parent) ─ */
%macro _derive_root_from_program(out=ROOT);
  %local full code_dir parent last;
  %let full=%sysfunc(dequote(&_SASPROGRAMFILE));         /* full path to the program you clicked Run on */
  %if %length(&full)=0 %then %do;                         /* fallback for rare contexts */
    %let &out=;
    %return;
  %end;

  /* directory of that program */
  %let last    = %scan(&full,-1,'/');                     /* file name */
  %let code_dir= %substr(&full,1,%eval(%length(&full)-%length(&last)-1));   /* .../BWIN621_Project/sas */

  /* parent of that directory → repo root */
  %let last    = %scan(&code_dir,-1,'/');                 /* 'sas' */
  %let parent  = %substr(&code_dir,1,%eval(%length(&code_dir)-%length(&last)-1)); /* .../BWIN621_Project */
  %let &out    = &parent;
%mend;

%global root;
%if %superq(root_override) ne %then %let root=&root_override;
%else %do;
  %_derive_root_from_program(out=root);
  /* if still blank, last fallback to typical Viya home layout */
  %if %length(&root)=0 %then %let root=/export/viya/homes/&sysuserid./casuser/BWIN621_Project;
%end;

/* ── Canonical folders under the repo ──────────────────────────────── */
%let RAW_PATH=&root./data/raw;
%let WRK_PATH=&root./data/wrk;
%let RES_PATH=&root./results;

%macro ensure_dir(p);
  %if %sysfunc(fileexist("&p"))=0 %then %do;
    %local leaf parent;
    %let leaf  = %scan(&p,-1,'/');
    %let parent= %substr(&p,1,%eval(%length(&p)-%length(&leaf)-1));
    data _null_; rc=dcreate("&leaf","&parent"); run;
  %end;
%mend;

%ensure_dir(&RAW_PATH)
%ensure_dir(&WRK_PATH)
%ensure_dir(&RES_PATH)
%ensure_dir(&RES_PATH./eda)
%ensure_dir(&RES_PATH./models)
%ensure_dir(&RES_PATH./score)

/* ── Libraries & file refs ─────────────────────────────────────────── */
libname raw "&RAW_PATH";
libname wrk "&WRK_PATH";
libname res "&RES_PATH";
filename loans "&RAW_PATH/SmallBusinessLoans.xlsx";

/* ── ODS target for plots ──────────────────────────────────────────── */
ods listing gpath="&RES_PATH./eda";
ods graphics / reset width=7in height=5in imagemap;

/* ── Handy fileref for includes so everyone can write %include code(\"x.sas\") ─ */
filename code "&root./sas";

/* ── Visibility in log ─────────────────────────────────────────────── */
%put NOTE: root = &root;
%put NOTE: RAW  -> %sysfunc(pathname(raw));
%put NOTE: WRK  -> %sysfunc(pathname(wrk));
%put NOTE: RES  -> %sysfunc(pathname(res));
%put NOTE: CODE -> %sysfunc(pathname(code));
%put NOTE: Plots -> &RES_PATH./eda;
