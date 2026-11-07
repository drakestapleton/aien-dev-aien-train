(* DRA-15 / aien-train#26 P0 admission oracle (Spark hive card t_8cf72aaf).
   Submitted to the hosted WolframLanguageEvaluator (agenttools.wolfram.com MCP).
   It implements native/collective/fixtures/admission_v0.json from its text
   (check order, codes, response formula, persistence rule), not from the .om:
   it recomputes the three base identities (FNV-1a 64), every case's status,
   response and counters, the rendered stdout of the observation build
   (expected-a1.out) and of the one-case-per-process build (expected-cli.out),
   their SHA-256, agreement with the fixture's expect_status, and the
   overflow bound behind the value range check. *)
m64 = 2^64;
fnv[ints_List] := Module[{h = 14695981039346656037},
   Do[h = Mod[BitXor[h, byte]*1099511628211, m64],
    {byte, Flatten[Reverse[IntegerDigits[Mod[#, m64], 256, 8]] & /@ ints]}]; h];
b0 = {2, -1, 3, 1, 0, -2};
bAlt = ReplacePart[b0, 5 -> 1];
bOvr = ReplacePart[b0, 1 -> 65537];
u0 = Flatten[Table[{i - 3, i + 1}, {i, 0, 7}]];
v0 = Flatten[Table[{1, 3 - i, -1}, {i, 0, 7}]];
base = <|"B" -> b0, "U" -> u0, "V" -> v0, "X" -> {2, 3, 5},
   "perm" -> ConstantArray[1, 8], "score" -> {4, 11, 7, 9, 8, 0, 3, 2},
   "cgen" -> ConstantArray[7, 8], "drank" -> 1, "drows" -> 2, "dcols" -> 3,
   "dbase" -> fnv[b0], "dgen" -> 7, "rrank" -> 1, "rrows" -> 2, "rcols" -> 3,
   "rbase" -> fnv[b0], "rgen" -> 7, "k" -> 2, "mode" -> 0,
   "idx" -> {1, 3, 0, 0}, "ph" -> {1, -1, 1, 1}|>;
(* at[a, key, i, v]: element i (0-based) of list field key set to v *)
at[a_, key_, i_, v_] := Append[a, key -> ReplacePart[a[key], i + 1 -> v]];
st[a_, rules___] := Append[a, {rules}];
cases = {
   base,
   st[base, "drank" -> 2, "rrank" -> 2],
   st[base, "rrank" -> 2],
   st[base, "drows" -> 3, "rrows" -> 3],
   st[base, "dcols" -> 2, "rcols" -> 2],
   st[base, "rrows" -> 1],
   st[base, "rcols" -> 4],
   st[base, "dbase" -> 0, "rbase" -> 0],
   st[base, "rbase" -> 0],
   st[base, "rbase" -> BitXor[fnv[b0], 1]],
   st[base, "B" -> bAlt],
   st[base, "B" -> bAlt, "dbase" -> fnv[bAlt], "rbase" -> fnv[bAlt]],
   st[base, "rgen" -> 6],
   at[base, "cgen", 3, 6],
   at[base, "cgen", 1, 8],
   at[base, "cgen", 5, 6],
   st[base, "dgen" -> 9, "rgen" -> 9, "cgen" -> ConstantArray[9, 8]],
   st[base, "k" -> 0],
   st[base, "k" -> 4, "idx" -> {0, 2, 4, 6}, "ph" -> {1, 1, 1, 1}],
   at[at[st[base, "k" -> 1], "idx", 0, 6], "ph", 0, -1],
   st[base, "k" -> 3, "idx" -> {0, 4, 7, 0}, "ph" -> {1, -1, 1, 1}],
   at[base, "idx", 1, 8],
   at[base, "idx", 1, m64 - 1],
   at[base, "idx", 0, 7],
   at[base, "perm", 3, 0],
   at[base, "perm", 2, 0],
   at[base, "ph", 0, 0],
   at[base, "ph", 1, 2],
   at[base, "ph", 0, -1],
   at[base, "idx", 0, 3],
   st[base, "k" -> 3, "idx" -> {1, 3, 1, 0}, "ph" -> {1, 1, 1, 1}],
   st[base, "perm" -> base["score"], "score" -> ConstantArray[1, 8]],
   at[base, "perm", 5, 2],
   st[base, "mode" -> 1, "ph" -> {1, 1, 1, 1}],
   at[at[st[base, "mode" -> 1, "k" -> 1], "perm", 1, 0], "ph", 0, 1],
   st[base, "mode" -> 1, "k" -> 3, "ph" -> {1, -1, 1, 1}],
   st[base, "mode" -> 1, "k" -> 1, "perm" -> ConstantArray[0, 8]],
   st[base, "mode" -> 1, "k" -> 3, "perm" -> {1, 0, 0, 0, 0, 1, 0, 0}],
   st[base, "mode" -> 2],
   st[base, "X" -> {65536, -65536, 65536}],
   at[base, "X", 0, 65537],
   at[base, "X", 2, 2^62],
   at[base, "U", 6, -65537],
   st[base, "B" -> bOvr, "dbase" -> fnv[bOvr], "rbase" -> fnv[bOvr]],
   at[base, "U", 10, 70000],
   at[st[base, "mode" -> 1], "cgen", 3, 6]};
fixtureExpect = {0, -4, -4, -5, -5, -5, -5, -6, -6, -7, -7, 0, -8, -9, -9, 0, 0,
   -10, -11, 0, 0, -1, -1, 0, -2, 0, -3, -3, 0, -12, -12, -13, -13, 0, 0, 0,
   -14, -14, -16, 0, -15, -15, -15, -15, 0, -9};
uOf[c_, i_] := c["U"][[2 i + 1 ;; 2 i + 2]];
vOf[c_, i_] := c["V"][[3 i + 1 ;; 3 i + 3]];
admit[c_] := Catch[Module[{k, plan = {}, free, id, ph},
    If[c["drank"] != 1 || c["rrank"] != c["drank"], Throw[{-4, {}}]];
    If[c["drows"] != 2 || c["dcols"] != 3 || c["rrows"] != c["drows"] || c["rcols"] != c["dcols"], Throw[{-5, {}}]];
    If[c["dbase"] == 0 || c["rbase"] == 0, Throw[{-6, {}}]];
    If[c["rbase"] != c["dbase"], Throw[{-7, {}}]];
    If[fnv[c["B"]] != c["dbase"], Throw[{-7, {}}]];
    If[c["rgen"] != c["dgen"], Throw[{-8, {}}]];
    If[AnyTrue[c["perm"], ! MemberQ[{0, 1}, #] &], Throw[{-13, {}}]];
    If[! MemberQ[{0, 1}, c["mode"]], Throw[{-16, {}}]];
    k = c["k"];
    If[k == 0, Throw[{-10, {}}]];
    If[k > 3, Throw[{-11, {}}]];
    If[c["mode"] == 0, plan = Take[c["idx"], k],
     Do[free = Select[Range[0, 7], c["perm"][[# + 1]] == 1 && ! MemberQ[plan, #] &];
      If[free === {}, Throw[{-14, {}}]];
      AppendTo[plan, First[MaximalBy[free, c["score"][[# + 1]] &]]], {k}]];
    Do[id = plan[[j]]; ph = c["ph"][[j]];
     If[id >= 8, Throw[{-1, {}}]];
     If[c["perm"][[id + 1]] != 1, Throw[{-2, {}}]];
     If[c["cgen"][[id + 1]] != c["dgen"], Throw[{-9, {}}]];
     If[! MemberQ[{1, -1}, ph], Throw[{-3, {}}]];
     If[MemberQ[Take[plan, j - 1], id], Throw[{-12, {}}]], {j, k}];
    If[AnyTrue[Join[c["X"], c["B"], Flatten[{uOf[c, #], vOf[c, #]} & /@ plan]], Abs[#] > 65536 &], Throw[{-15, {}}]];
    {0, plan}]];
resp[c_, plan_] := Partition[c["B"], 3] . c["X"] +
   Total[Table[c["ph"][[j]] uOf[c, plan[[j]]] (vOf[c, plan[[j]]] . c["X"]), {j, Length[plan]}], 1];
s2 = Function[l, StringRiffle[ToString /@ l, " "]];
y = {0, 0}; cnt = {0, 0}; a1 = {}; cli = {}; statuses = {};
Do[{sts, plan} = admit[cases[[n + 1]]]; AppendTo[statuses, sts];
  If[sts == 0, y = resp[cases[[n + 1]], plan]; cnt = cnt + {1, Length[plan]}];
  AppendTo[a1, "A1 " <> s2[Join[{n, sts}, y, cnt]]];
  AppendTo[cli, s2[{n, -sts}] <> " " <> If[sts == 0, "Y " <> s2[y], "-"]], {n, 0, Length[cases] - 1}];
a1s = StringJoin[# <> "\n" & /@ Append[a1, "END"]];
clis = StringJoin[# <> "\n" & /@ cli];
mM = 65536;
<|"ids" -> {fnv[b0], fnv[bAlt], fnv[bOvr], BitXor[fnv[b0], 1]},
  "ncase" -> Length[cases], "statuses_match_fixture" -> (statuses === fixtureExpect),
  "a1" -> a1s, "a1_sha256" -> Hash[a1s, "SHA256", "HexString"],
  "cli" -> clis, "cli_sha256" -> Hash[clis, "SHA256", "HexString"],
  "bound" -> {3 mM^2 + 9 mM^3, 2^63 - 1, 3 mM^2 + 9 mM^3 < 2^63 - 1},
  "huge_row0" -> 2*2 + (-1)*3 + 3*2^62 > 2^63 - 1|>
