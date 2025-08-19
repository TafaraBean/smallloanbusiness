/**************************************************************************
* 00_env.sas — Portable bootstrap for SAS Viya + GitHub repo
**************************************************************************/
options dlcreatedir fullstimer;

/* Optional manual override (leave blank for auto-detect) */
%let root_override=;

/* ---- One macro to do everything (no nested %IF in open code) ---- */
%macro setup_env();
  %global root RAW_PATH WRK_PATH RES_PATH;

  /* 1) Resolve &root */
  %if %length(%superq(root_override))>0 %then %let root=&root_override;
  %else %do;
    %local full code_dir parent last;
    %let full=%sysfunc(dequote(&_SASPROGRAMFILE));
    %if %length(&full)>0 %then %do;
      %let last     = %scan(&full,-1,'/');                                        /* file.sas         */
      %let code_dir = %substr(&full,1,%eval(%length(&full)-%length(&last)-1));    /* …/repo/sas       */
      %let last     = %scan(&code_dir,-1,'/');                                    /* 'sas'            */
      %let parent   = %substr(&code_dir,1,%eval(%length(&code_dir)-%length(&last)-1)); /* …/repo       */
      %let root     = &parent;
    %end;
    %else %let root=/export/viya/homes/&sysuserid./casuser/BWIN621_Project;
  %end;

  /* 2) Canonical paths (your structure) */
  %let RAW_PATH=&root./data/raw;
  %let WRK_PATH=&root./data/wrk;
  %let RES_PATH=&root./results;

  /* 3) Ensure folders exist (including parents) */
  %macro ensure_dir(p);
    %local leaf parent;
    %if %sysfunc(fileexist("&p"))=0 %then %do;
      %let leaf  = %scan(&p,-1,'/');
      %let parent= %substr(&p,1,%eval(%length(&p)-%length(&leaf)-1));
      %if %sysfunc(fileexist("&parent"))=0 %then %do;
        %local pleaf pparent;
        %let pleaf   = %scan(&parent,-1,'/');
        %let pparent = %substr(&parent,1,%eval(%length(&parent)-%length(&pleaf)-1));
        data _null_; rc=dcreate("&pleaf","&pparent"); run;
      %end;
      data _null_; rc=dcreate("&leaf","&parent"); run;
    %end;
  %mend;
  %ensure_dir(&root./data)
  %ensure_dir(&RAW_PATH)
  %ensure_dir(&WRK_PATH)
  %ensure_dir(&RES_PATH)
  %ensure_dir(&RES_PATH./eda)
  %ensure_dir(&RES_PATH./models)
  %ensure_dir(&RES_PATH./score)

  /* 4) Libraries & file refs */
  libname raw "&RAW_PATH";
  libname wrk "&WRK_PATH";
  libname res "&RES_PATH";
  filename loans "&RAW_PATH/SmallBusinessLoans.xlsx";
  filename code  "&root./sas";

  /* 5) ODS for plots */
  ods listing gpath="&RES_PATH./eda";
  ods graphics / reset width=7in height=5in imagemap;

  /* 6) Visibility */
  %put NOTE: Program -> &_SASPROGRAMFILE;
  %put NOTE: root    = &root;
  %put NOTE: RAW_PATH= &RAW_PATH;
  %put NOTE: WRK_PATH= &WRK_PATH;
  %put NOTE: RES_PATH= &RES_PATH;
  %put NOTE: Excel exists? -> %sysfunc(fileexist("&RAW_PATH/SmallBusinessLoans.xlsx"));
%mend;

%setup_env()

