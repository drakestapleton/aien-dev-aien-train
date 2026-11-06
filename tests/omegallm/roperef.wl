(* tests/omegallm/roperef.wl: Wolfram generator for tests/omegallm/roperef.txt (v4 ropeck).
   Each line is "s XBITS RBITS" or "c XBITS RBITS" (16 lowercase hex digits). RBITS is the
   round-half-even f64 of a 60-digit Sin/Cos at the exact f64 XBITS (rb/sb as in mathref.wl).
   Angles cover [0, 16400] rad: an even grid, multiples of Pi/2, 12 seeded random points and
   edge values. Text = lines joined by "\n" plus a final "\n" (64 angles, 128 lines, 4608 bytes,
   sha256 94fe7c6ce9cb440d00af2c25b70096983e02bb4d8a27a91e76fcdb79dc8b8d28). *)
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
sn[x_Real] := Module[{r = SetPrecision[x, Infinity]}, "s " <> hx[xb[x]] <> " " <> hx[sb[N[Sin[r], 60]]]];
cs[x_Real] := Module[{r = SetPrecision[x, Infinity]}, "c " <> hx[xb[x]] <> " " <> hx[sb[N[Cos[r], 60]]]];
SeedRandom[20261106];
xs = Join[Table[N[k*16400/31], {k, 0, 31}], N[Table[k Pi/2, {k, 1, 10433, 1043}]], N[Table[k Pi/2, {k, 2, 4}]],
  RandomReal[{0, 16400}, 12], {1.*^-9, 0.5, 1., 2047., 2048., 16384.}];
xs = DeleteDuplicates[Select[xs, MachineNumberQ]];
text = StringRiffle[Join[sn /@ xs, cs /@ xs], "\n"] <> "\n";
Export["roperef.txt", text, "String"];
