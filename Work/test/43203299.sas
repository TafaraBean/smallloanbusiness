proc iml;

T=1; Nt=24; M=20; Smax=200; r=0.075; q=0; sig=0.15; S0=100;
dS=Smax/M; dt=T/Nt; S=t(0:M)*dS; j=t(1:M-1); s2=sig##2;


a=-0.25*dt*((r-q)#j) + 0.25*dt*(s2#(j##2));
b=-0.5*dt*r            - 0.5*dt*(s2#(j##2));
g= 0.25*dt*((r-q)#j) + 0.25*dt*(s2#(j##2));
nInt=M-1; A=j(nInt,nInt,0); B=A;
do k=1 to nInt; 
  A[k,k]=1-b[k];  B[k,k]=1+b[k];
  if k>1    then do; A[k,k-1]=-a[k]; B[k,k-1]= a[k]; end;
  if k<nInt then do; A[k,k+1]=-g[k]; B[k,k+1]= g[k]; end;
end;


allow=j(Nt,1,0); idx={2 4 6 8 18 20 22 24}; allow[idx]=1;


V=j(M+1,1,0); KT=105; p=loc(KT-S>0); if ncol(p)>0 then V[p]=(KT-S)[p];


do i=Nt-1 to 0 by -1;
  t=i*dt; K=110; if t>0.5 then K=105;
  V0=K*exp(-r*(T-t)); VM=0;

  y=V[2:M]; rhs=B*y;
  rhs[1]    = rhs[1]    + a[1]*(V[1]+V0);
  rhs[nInt] = rhs[nInt] + g[nInt]*(V[M+1]+VM);

  x = solve(A, rhs);                 

  V=0*V; V[1]=V0; V[2:M]=x; V[M+1]=VM;
  if allow[i+1]=1 then do; ex=K-S; q=loc(ex>V & ex>0); if ncol(q)>0 then V[q]=ex[q]; end;
end;

j0=round(S0/dS)+1; price=V[j0];
print price[label="Option value (S0=100)"];
quit;
