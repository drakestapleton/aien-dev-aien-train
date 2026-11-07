(* DRA-15 / aien-train#26 P0 independent oracle, submitted 2026-11-07 to the
   hosted WolframLanguageEvaluator (agenttools.wolfram.com MCP) by t_60180a9d.
   It recomputes base, all 16 signed rank-one outputs, top-2 admitted
   selection, deny-1 selection and the all-denied sentinel, and renders the
   exact expected stdout of the observation build. The status line
   "-2 -1 -3" transcribes the precommitted refusal codes of golden_v0.json
   (invalid index -1, denied -2, bad phase -3); it is a contract, not
   arithmetic. Returned SHA-256 of the rendered string:
   829b9a67f432f070dd4fbaa44fab8401d6d9c614ceec3dd0d12555549881cfff, equal to
   native/collective/replay/expected-p0e1.out. *)
x = {2, 3, 5}; b = {{2, -1, 3}, {1, 0, -2}};
u[i_] := {i - 3, i + 1}; v[i_] := {1, 3 - i, -1};
out[i_, s_] := b . x + s u[i] (v[i] . x);
scores = {4, 11, 7, 9, 8, 0, 3, 2};
topIdx[allowedIds_, used_] := Module[{c = Complement[allowedIds, used]}, If[c === {}, 8, First[MaximalBy[c, scores[[# + 1]] &]]]];
all = Range[0, 7];
t1 = topIdx[all, {}]; t2 = topIdx[all, {t1}]; d1 = topIdx[DeleteCases[all, 1], {}]; ad = topIdx[{}, {}];
s2 = Function[l, StringRiffle[ToString /@ l, " "]];
lines = Join[{"P0E1 base " <> s2[b . x]},
   Flatten[Table["P0E1 y " <> s2[Join[{i, s, 0}, out[i, s]]], {i, 0, 7}, {s, {1, -1}}]],
   {"P0E1 top2 " <> s2[{t1, t2}], "P0E1 deny1top " <> s2[{d1}], "P0E1 status -2 -1 -3", "P0E1 alldenied " <> s2[{ad}], "P0E1 counts 1 16", "END"}];
{StringJoin[# <> "\n" & /@ lines], Hash[StringJoin[# <> "\n" & /@ lines], "SHA256", "HexString"], {8*6, 6 + 8*(2 + 3)}, Table[{i, out[i, 1], out[i, -1]}, {i, 0, 7}]}
