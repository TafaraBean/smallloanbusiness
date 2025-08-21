/*===============================================================
  01_import.sas — Excel → RAW.LOANS (simple, idempotent)
  - Includes 00_env.sas (no hard-coded paths)
  - Imports first sheet by default (or supply a sheet=)
===============================================================*/

/* 0) Bootstrap environment (portable include from this file's folder) */
%let _pgm=%sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir=%substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";

/* 1) Import macro (does nothing if RAW.LOANS already exists) */
%macro import_loans(sheet=, out=raw.loans, guess=32767);

  /* a) Excel present? (&loans is a FILEREF created in 00_env.sas) */
  %if %sysfunc(fexist(loans)) = 0 %then %do;
    %put ERROR: Excel not found at &RAW_PATH/SmallBusinessLoans.xlsx ;
    %return;
  %end;

  /* b) Already imported? */
  %if %sysfunc(exist(&out)) %then %do;
    %put NOTE: &out already exists — skipping import.;
    %return;
  %end;

  /* c) Import (PROC IMPORT with DBMS=XLSX) */
  %if %superq(sheet)= %then %do;
    proc import datafile=loans out=&out dbms=xlsx replace;
      getnames=yes; guessingrows=&guess;
    run;
  %end;
  %else %do;
    proc import datafile=loans out=&out dbms=xlsx replace;
      sheet="&sheet"; getnames=yes; guessingrows=&guess;
    run;
  %end;

  proc contents data=&out; title "Imported: &out"; run;
%mend;

/* 2) Call it (no sheet name → first sheet) */
%import_loans()
title;
