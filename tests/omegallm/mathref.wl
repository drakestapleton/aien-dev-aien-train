(* tests/omegallm/mathref.wl: Wolfram generator for tests/omegallm/mathref.txt (aien-train#52).
   Each line is "e XBITS RBITS" or "l XBITS RBITS" (16 lowercase hex digits). RBITS is the
   round-half-even f64 of a 60-digit Exp/Log at the exact f64 XBITS, built bit by bit (subnormal,
   overflow and zero cases explicit). Text = lines joined by "\n" plus a final "\n". *)
rb[v_] := Module[{e, m},
  e = Floor[Log2[v]];
  If[e < -1022, Return[Round[v*2^1074]]];
  m = Round[v*2^(52 - e)];
  If[m == 2^53, e = e + 1; m = 2^52];
  If[e > 1023, Return[2047*2^52]];
  (e + 1023)*2^52 + m - 2^52];
sb[v_] := Which[v == 0, 0, v > 0, rb[v], True, 2^63 + rb[-v]];
hx[b_] := IntegerString[b, 16, 16];
xb[x_Real] := sb[SetPrecision[x, Infinity]];
ex[x_Real] := Module[{r = SetPrecision[x, Infinity]}, "e " <> hx[xb[x]] <> " " <> hx[sb[N[Exp[r], 60]]]];
lg[x_Real] := Module[{r = SetPrecision[x, Infinity]}, "l " <> hx[xb[x]] <> " " <> hx[If[r == 1, 0, sb[N[Log[r], 60]]]]];
xe = Join[Table[N[k/1000], {k, -1000, 1000}], Table[N[-745 + i*145478/99900], {i, 0, 999}],
  {709.782712893384, 709.7827128933841, 709.79, 710., -708.39, -708.4, -720., -745.13, -745.1332191019412, -745.14, -745.2, -800., 0.5*Log[2.], Log[2.], 1.*^-300, -1.*^-300, 1.*^-17}];
xl = Join[Table[N[1/2 + k/1000], {k, 0, 1500}], Table[N[10^k], {k, -307, 307}],
  {5.*^-324, 1.*^-310, 2.2250738585072014*^-308, 2.225073858507201*^-308, 1.7976931348623157*^308, 1.0000000000000002, 0.9999999999999999, 2.718281828459045}];
xe = DeleteDuplicates[Select[xe, MachineNumberQ]]; xl = DeleteDuplicates[Select[xl, MachineNumberQ]];
text = StringRiffle[Join[ex /@ xe, lg /@ xl], "\n"] <> "\n";
