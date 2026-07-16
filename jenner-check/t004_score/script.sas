/*===============================================================
   Adapted from sas/05_score.sas (production scoring with PD +
   Points, confusion matrix + metrics). Original author: Tapiwa
   Gweshe.
   Adaptation: MODELS/SCORE libnames and the wrk.hold/wrk.dev
   picker are replaced by fitting the same two PROC LOGISTIC models
   as sas/04_model.sas directly against an inline 80-row sample
   (same rows/columns used in this bundle set) and scoring that
   same set. The PD->Points PDO transform and the confusion-matrix
   macro (_cm_metrics) are copied verbatim from the source script.
===============================================================*/

data raw_loans;
  infile datalines dlm='|' dsd missover;
  length Name $40 RevLineCr $1;
  input Selected LoanNr_ChkDgt Name $ Zip Term NoEmp CreateJob RetainedJob
        FranchiseCode UrbanRural RevLineCr $ DisbursementGross BalanceGross
        WrittenOff New RealEstate Portion Recession Default;
  datalines;
1|2280915007|Parkside Postal|94116|84|1|1|0|0|1|N|10000|0|0|1|0|0.85|0|0
1|2117256006|JEDEDIAH GROUP INC|91914|275|2|0|2|1|1|0|590600|0|302116|1|1|0.75|0|1
0|2082246002|AMBER HUSSAIN REALTOR|92882|35|1|2|3|1|1|Y|11688|0|4466|0|0|0.5|0|1
0|1196525000|TR Benefits Insurance Services|94526|84|4|0|4|1|1|Y|58602|0|0|0|0|0.5|0|0
1|2906856001|LEGAL TENDER INC|92028|51|2|0|2|1|1|Y|24190|0|9231|1|0|0.5|0|1
1|2649925000|PIANA HOLDINGS INC|92807|109|3|2|3|0|1|N|10000|0|9729|0|0|0.85|0|1
0|1241435008|Los Angeles Properties Inc. D|90504|30|16|0|16|1|1|N|81937|0|48632|0|0|0.5|0|1
0|2107375007|Pinnacle Homes and Loans|92127|33|1|0|1|0|1|N|62500|0|35000|0|0|0.5|0|1
1|7586944004|SCOTT T SHORT|95822|84|1|1|1|1|1|Y|47179|0|0|0|0|0.5|0|0
0|7520534007|ADZ CORPORATION|95661|59|58|2|7|1|1|Y|91075|0|0|0|0|0.5|0|0
1|5696164008|GALLERY PROPERTIES|92037|60|2|0|2|1|1|Y|43978|0|0|0|0|0.5|1|0
1|7335084001|CONTRACTORS EQUIPMENT RENTALS|93308|84|7|1|7|1|1|Y|200000|0|0|0|0|0.5|0|0
0|6134804002|ACACIA EXECUTIVE SERVICES INC|91765|84|5|0|5|1|1|Y|50000|0|0|0|0|0.5|0|0
1|2174685006|ROYSTARICA INC.|92109|59|5|3|8|0|1|Y|40808|0|19690|0|0|0.5|0|1
0|1113545001|Boels Inc. dba Automated Regi|92708|84|8|0|0|1|1|N|100000|0|0|0|0|0.5|0|0
1|7824123005|PLACER TV INC|95825|300|2|0|0|1|0|N|500000|0|0|0|1|0.7|0|0
1|8931234010|JAHANGIR G. FAGHIHI|91302|3|2|10|2|1|1|0|10000|0|161|0|0|0.85|0|1
1|7699594002|INFUSION COMPLETE|92673|84|2|5|7|1|1|Y|164502|0|0|0|0|0.5|0|0
1|9066294005|OXFORD LAND DEVELOPMENT LLC|91101|25|1|0|1|1|1|Y|16792|0|3980|1|0|0.5|0|1
0|3151956002|BUNCH CORPORATION|85008|120|5|0|5|1|1|0|575000|0|0|0|0|0.75|0|0
1|7437904010|BRIAR GROUP|90802|300|2|2|4|1|1|0|500000|0|0|0|1|0.75|0|0
0|5497084005|BROADCAST PLUS|91367|300|6|0|0|1|1|N|1000000|0|0|0|1|0.75|0|0
1|9925643006|TAHOE MOTION PICTURE RENTALS|91352|120|3|0|0|1|0|0|251150|0|0|0|0|0.75|0|0
0|5084914007|BOUNCE THIS|92802|84|1|0|0|1|1|N|50000|0|0|1|0|0.85|1|0
0|2793505008|DAVID CANGELOSI|92807|64|1|0|0|0|1|Y|19260|0|10000|0|0|0.5|0|1
0|2032135010|Central Capital Corporation|91016|45|6|0|6|0|1|Y|121612|0|49701|0|0|0.5|0|1
0|1994155001|US Portfolio Services Inc.|92107|70|2|0|2|0|1|Y|44581|0|22353|0|0|0.5|0|1
0|1904875002|Silverwood Mortgage Inc.|90071|51|7|0|7|0|1|N|75000|0|35000|0|0|0.5|0|1
0|2762435008|Strategic Mortgage Corporation|91789|84|6|0|6|0|1|Y|12350|0|0|0|0|0.5|0|0
1|9779454005|PRESTIGE PROPERTIES OF RANCHO|92130|42|1|0|1|1|1|0|25000|0|21729|0|0|0.85|0|1
1|1088625009|Michael L. Judson dba Linex Co|94901|84|4|0|0|1|1|N|39000|0|0|0|0|0.5|0|0
1|2174116006|RE MAX LEGACY|96001|240|13|37|13|68060|2|0|389000|0|0|0|1|1|0|0
1|1802786005|PROPERTY APPRAISALS|94403|35|4|0|4|1|1|Y|26582|0|6651|0|0|0.5|1|1
0|1408404006|WARFIELD ENTERPRISES INC.|92234|300|9|0|0|1|0|0|257000|0|0|0|1|0.75|0|0
0|4984573006|BLOCKBUSTER VIDEO R|90746|78|25|0|0|1|0|N|675000|0|128378|1|0|0.85|0|1
1|7108044000|RONNIES TUXEDOS|93401|106|10|0|0|1|1|0|150000|0|143620|0|0|0.85|0|1
1|2826415002|FUN 2 GO|92683|3|8|0|8|0|1|Y|79800|0|49809|0|0|0.5|1|1
1|1717255009|GOOD LAND INCHRIST INC.|92832|60|4|1|4|0|1|N|100000|0|85306|1|0|0.5|0|1
1|1159915000|Westec Mortgage Inc.|91730|49|3|2|3|1|1|T|69500|0|50000|0|0|0.5|1|1
1|5641834000|BUDGET RENT A CAR OF MODESTO|95358|240|3|3|0|1|1|N|138000|0|0|0|1|1|0|0
0|8816154004|LAX EQUIPMENT INC|90301|300|10|0|10|1|1|0|297500|0|0|0|1|0.75|0|0
1|3308865002|SEPIA FINANCIAL SERVICES INC.|92648|82|1|0|1|0|1|N|7500|0|5833|0|0|0.85|0|1
1|6219074007|ADAMS AVENUE RENTALS  SALES|92116|300|1|0|1|1|1|0|508500|0|0|0|1|0.75|0|0
1|7194924010|PETERSEN EVENTS CORP A CALIFOR|91006|240|4|6|0|1|1|0|207000|0|0|0|1|1|0|0
0|8838464004|EDUARD RUBALCABA|93638|18|1|0|0|1|1|Y|16679|0|4034|1|0|0.5|0|1
1|8350884008|SAMS VIDEO|92844|59|2|2|2|1|1|Y|50000|0|0|0|0|0.5|0|0
1|4292174010|ANGELLOS ATV|93401|300|10|0|0|1|2|N|409500|0|0|0|1|0.75|0|0
0|2169625005|The Bond Group|92104|65|1|1|1|0|1|Y|110000|0|100000|0|0|0.5|0|1
0|1077145001|DESERT REALTY  DEVELOPMENT CO|90305|67|12|0|0|1|1|N|50000|0|50000|0|0|0.5|0|1
1|1472284001|AJAX RENT A CAR|90004|300|7|0|0|1|0|0|720000|0|0|0|1|0.75|0|0
0|3336545008|GREEN BAND ENTERPRISES LLC|91750|110|2|2|2|0|1|N|10000|0|9645|0|0|0.85|0|1
1|1207665003|P T J Enterprise Incorporated|90305|68|4|0|4|1|1|T|45018|0|45000|0|0|0.5|0|1
0|2730566003|MOVING VEHICULAR PLATFORMS INC|91784|120|3|0|3|1|1|0|450000|0|0|0|0|0.75|0|0
1|2169086005|CASAS USA|91910|277|4|0|0|1|1|N|640700|0|37919|0|1|0.75|0|1
1|6093234000|JBJ PIPE  SUPPLY CO.|92683|300|2|0|0|1|1|N|500000|0|0|0|1|0.75|0|0
1|2710626000|PORTER RENTS INC|95370|84|3|0|3|1|1|N|41471|0|0|0|0|0.5|0|0
0|2061995009|Better Model Realty  Ltd.|95816|84|1|0|1|0|1|Y|13000|0|0|1|0|0.5|0|0
1|2950195005|RAFAEL REYES SPINDOLA  DBA  Re|95825|72|1|0|1|0|1|N|50000|0|47462|0|0|0.5|0|1
1|1851615000|MARTIN BERNARD PEARSON DBA PEA|91784|84|4|2|4|0|1|N|25000|0|0|0|0|0.5|0|0
1|1033135007|Mitchell J Kemp dba Pacific Co|94103|84|1|0|0|1|1|Y|17536|0|0|0|0|0.5|0|0
1|3234444005|VALLEY VIDEO|96022|300|4|4|4|1|1|0|180000|0|0|0|1|0.75|0|0
1|1823175002|Birchleaf Inc. dba Hidden Riv|94513|51|5|0|5|0|1|N|39384|0|24245|1|0|0.5|0|1
0|5737794006|ACTION VIDEO|93247|240|4|4|0|1|2|N|128000|0|0|0|1|1|0|0
0|7589794002|EMPIRE CRANE SERVICE|92313|36|1|0|1|1|1|Y|10215|0|0|0|0|0.5|0|0
0|3633394000|COAST  COUNTY REAL ESTATE|92054|52|6|0|6|1|1|0|125000|0|103524|0|0|0.75|0|1
0|3877874009|MAX EQUIPMENT RENTAL LLC|95069|180|3|2|5|1|1|0|500000|0|0|1|0|0.75|0|0
0|1122875008|Patty Schwartzkopf Properties|93546|84|2|0|0|1|2|Y|11000|0|0|0|0|0.5|0|0
0|9139364004|CORNERSTONE REAL ESTATE AND HO|94558|240|13|10|0|1|1|0|286000|0|0|0|1|1|0|0
0|7815224005|SIGNATURE MRI SALES  SERVICES|90066|36|1|0|1|1|1|Y|60014|0|0|0|0|0.5|0|0
0|2098565002|MMTC FINANCIAL CORP.|94123|90|2|4|2|0|1|N|50000|0|0|0|0|0.5|0|0
0|2932065008|ELIZABETH CHRISTINA MADRID DBA|93274|44|5|0|5|0|1|Y|114584|0|47529|0|0|0.5|0|1
0|3334525009|VIDEO WORLD|94044|84|2|1|2|0|1|N|25000|0|0|0|0|0.85|0|0
0|7060144006|CRAE REALTY  TAX SERVICES|93003|34|1|1|1|1|1|T|6000|0|5224|0|0|0.5|0|1
0|8670184009|BENCHMARK REALTY  FINANCE|95112|263|2|0|2|1|1|0|675000|0|197158|0|1|0.75|0|1
1|1841775009|THOMAS WILLIAM CUNNINGHAM DBA|92025|62|1|0|1|0|1|N|50000|0|44319|0|0|0.5|0|1
1|4152844008|HORVATH GENERATORS|91352|120|3|1|3|1|1|0|100000|0|0|0|0|0.75|0|0
0|7449944008|CA HEHL AND ASSOCIATES|92648|84|1|0|1|1|1|Y|14500|0|0|0|0|0.5|0|0
0|1168925005|Desert Resort Management Inc.|92260|84|58|4|58|1|1|N|100000|0|0|0|0|0.5|0|0
0|1939816002|PROVIDENCE REAL ESTATE SERVICE|95148|279|12|0|12|1|1|0|441000|0|181156|0|1|0.75|0|1
1|6268354004|PUSAN VIDEO|94612|96|3|0|0|1|1|0|110000|0|0|0|0|0.85|0|0
;
run;

/* Cleaning, matching 03_clean.sas rules */
data dev;
  set raw_loans;
  length _rev $12;
  _rev = upcase(strip(cats(RevLineCr)));
  if      _rev in ('1','Y','YES','T','TRUE') then RevLineCr_num=1;
  else if _rev in ('0','N','NO','F','FALSE') then RevLineCr_num=0;
  else                                        RevLineCr_num=0;
  drop RevLineCr _rev;
  rename RevLineCr_num=RevLineCr;

  _fc = inputn(cats(FranchiseCode),'best32.');
  if missing(_fc) then FranchiseCode=.;
  else FranchiseCode = (_fc>1);
  drop _fc;

  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

%let xlist = Term NoEmp CreateJob RetainedJob FranchiseCode
             UrbanRural RevLineCr RealEstate Recession
             DisbursementGross Portion;

/* E) Add row id for safe merge */
data _toscore_;
  set dev;
  _rid_=_n_;
run;

/* F) Fit + score BOTH models in one step (probability of default only).
   05_score.sas fits once in 04_model.sas then re-scores via PROC LOGISTIC
   INMODEL=/SCORE in a later run; here the two steps are combined so the
   bundle is self-contained: OUTPUT OUT=...P= scores the same DATA= used
   to fit, which is equivalent for this single-dataset case. */
ods exclude all; ods results off;
proc logistic data=_toscore_ desc plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default = &xlist;
  output out=_full_scored(keep=_rid_ Default PD_full) p=PD_full;
run;

proc logistic data=_toscore_ desc plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default = &xlist / selection=stepwise slentry=0.05 slstay=0.05;
  output out=_step_scored(keep=_rid_ PD_step) p=PD_step;
run;
ods exclude none; ods results on;

/* G) Merge and PD difference -> dev_scored */
data dev_scored;
  merge _full_scored _step_scored;
  by _rid_;
  PD_diff = PD_step - PD_full;
run;

/* H) PD -> Points (PDO method) with clipping to avoid infinities */
%let BaseScore = 600;   /* score at BaseOdds */
%let BaseOdds  = 50;    /* non-default:default odds at BaseScore */
%let PDO       = 20;    /* points to double the odds */
%let Pmin      = 1e-6;
%let Pmax      = 0.999999;

data dev_scored;
  set dev_scored;
  _p = min(max(PD_full,&Pmin),&Pmax);
  _q = min(max(PD_step,&Pmin),&Pmax);

  Points_full = &BaseScore + (&PDO/log(2))*( log((1-_p)/_p) - log(&BaseOdds) );
  Points_step = &BaseScore + (&PDO/log(2))*( log((1-_q)/_q) - log(&BaseOdds) );

  drop _p _q;
run;

/* I) Console output */
title "Scoring preview: PDs and Points (first 15)";
proc print data=dev_scored(obs=15) noobs;
  var Default PD_full PD_step PD_diff Points_full Points_step;
run;

title "Scoring summary: PDs and Points";
proc means data=dev_scored n mean p25 p50 p75 min max maxdec=4;
  var PD_full PD_step PD_diff Points_full Points_step;
run; title;

/* ---------- Confusion matrix + metrics for any (PD, cut) ---------- */
%macro _cm_metrics(data=, y=Default, p=, cut=, label=);
  data __tmp;
    set &data;
    length _pred 8;
    _pred = (&p >= &cut);
  run;

  proc freq data=__tmp noprint;
    tables &y.*_pred / out=__cm;
  run;

  proc sql noprint;
    select sum(count) into :_N      from __cm;
    select sum(count) into :_TP     from __cm where &y.=1 and _pred=1;
    select sum(count) into :_TN     from __cm where &y.=0 and _pred=0;
    select sum(count) into :_FP     from __cm where &y.=0 and _pred=1;
    select sum(count) into :_FN     from __cm where &y.=1 and _pred=0;
  quit;

  data __metrics;
    length Model $48;
    N  = input(symget('_N'), best.);
    TP = input(symget('_TP'),best.);
    TN = input(symget('_TN'),best.);
    FP = input(symget('_FP'),best.);
    FN = input(symget('_FN'),best.);

    Model = "&label"; Cut = &cut;
    Accuracy     = (TP+TN)/max(N,1);
    Sensitivity  = TP/max(TP+FN,1);
    Specificity  = TN/max(TN+FP,1);
    Precision    = TP/max(TP+FP,1);
    NPV          = TN/max(TN+FN,1);
    FPR          = 1-Specificity;
    FNR          = 1-Sensitivity;
    F1           = ifn(Precision+Sensitivity>0, 2*Precision*Sensitivity/(Precision+Sensitivity), .);
    BalancedAcc  = (Sensitivity+Specificity)/2;
    YoudenJ      = Sensitivity + Specificity - 1;
    Prevalence   = (TP+FN)/max(N,1);
    PredPosRate  = (TP+FP)/max(N,1);
    MCC_den      = sqrt(max((TP+FP)*(TP+FN)*(TN+FP)*(TN+FN),1));
    MCC          = ((TP*TN)-(FP*FN)) / MCC_den;
    drop MCC_den;
  run;

  title "Confusion matrix — &label";
  proc print data=__cm noobs; run;
  title "Metrics — &label";
  proc print data=__metrics noobs; run;
  title;

  proc datasets nolist; delete __tmp __cm __metrics; quit;
%mend;

%_cm_metrics(data=dev_scored, y=Default, p=PD_full, cut=0.5, label=Full @0.5);
%_cm_metrics(data=dev_scored, y=Default, p=PD_step, cut=0.5, label=Stepwise @0.5);
