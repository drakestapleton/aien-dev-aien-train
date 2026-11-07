-- SPDX-License-Identifier: AGPL-3.0-only
/-
DRA-146 personal memory: supersession invariant (core Lean 4, no Mathlib). Checked with the `lean` MCP
server (`lean_run_code`) on 2026-11-07; every theorem's axioms are within
[propext, Classical.choice, Quot.sound]; no sorry.

Model-to-system link (hand-copied, checked by reading): native/personal/mem.om `resolve` first applies the
explicit links of the log (correct T -> T superseded, retract T -> T retracted): that is `Rec.st` here. Then
`idwin` keeps an explicitly active record active only if no asserted (add or correct) record of the same
identity (`rih` + `rkd`: kind and normalized key; `Rec.key` here), whatever its final status, is `newer` by
(ts, rid) lexicographic (`newer` here, `tscmp` + rid). `cquery`/`qtop` rank only records whose final status is
active (`retrieve` here). Retract events are not records of the model. The negative-control build mem-nosup
(OMSUP 0) keeps every add/correct record (`retrieveNoSup`).
Revision after review (head 24f14cb7): identity supersession used to count only explicitly ACTIVE newer
records, so retracting a replacement revived its predecessor. Now any newer asserted record counts, and
`status_edit_no_revive` proves that a status edit (retract or explicit supersede) of one record never changes
whether any other record is current. The theorem is about this model; tests/personal/mem-check.sh exercises
the binary (case `revive`).
-/
namespace Dra146Mem

inductive St | active | superseded | retracted
  deriving DecidableEq, Repr

structure Rec where
  key : Nat
  ts : Nat
  idx : Nat
  st : St
  deriving DecidableEq, Repr

def newer (a b : Rec) : Bool := decide (b.ts < a.ts) || (decide (b.ts = a.ts) && decide (b.idx < a.idx))

/-- no asserted record of the same key, whatever its status, is newer -/
def newest (rs : List Rec) (r : Rec) : Bool :=
  rs.all (fun r' => !(decide (r'.key = r.key) && newer r' r))

def finalActive (rs : List Rec) (r : Rec) : Bool :=
  decide (r.st = St.active) && newest rs r

def retrieve (rs : List Rec) (k : Nat) : List Rec :=
  rs.filter (fun r => decide (r.key = k) && finalActive rs r)

theorem retrieve_key (rs : List Rec) (k : Nat) (r : Rec) (h : r ∈ retrieve rs k) : r.key = k := by
  simp [retrieve] at h
  exact h.2.1

theorem retrieve_active (rs : List Rec) (k : Nat) (r : Rec) (h : r ∈ retrieve rs k) :
    r.st = St.active := by
  simp [retrieve, finalActive] at h
  exact h.2.2.1

/-- retrieval never returns an explicitly superseded or retracted record -/
theorem retrieve_never_superseded (rs : List Rec) (k : Nat) (r : Rec) (h : r ∈ retrieve rs k) :
    r.st ≠ St.superseded ∧ r.st ≠ St.retracted := by
  have := retrieve_active rs k r h
  rw [this]; exact ⟨by decide, by decide⟩

/-- the retrieved record is the max-(ts, rid) record of its key among ALL asserted records -/
theorem retrieve_max (rs : List Rec) (k : Nat) (r : Rec) (h : r ∈ retrieve rs k)
    (r' : Rec) (h' : r' ∈ rs) (hk : r'.key = k) :
    r'.ts < r.ts ∨ (r'.ts = r.ts ∧ r'.idx ≤ r.idx) := by
  simp [retrieve, finalActive, newest] at h
  obtain ⟨_, hrk, _, hall⟩ := h
  rcases hall r' h' with hn | hn
  · exact absurd (by rw [hk, hrk]) hn
  · simp [newer] at hn
    omega

/-- with distinct rids there is at most one current record per key (the same-ts tie goes to the larger rid) -/
theorem retrieve_unique (rs : List Rec) (k : Nat) (r1 r2 : Rec)
    (hid : ∀ a ∈ rs, ∀ b ∈ rs, a.idx = b.idx → a = b)
    (h1 : r1 ∈ retrieve rs k) (h2 : r2 ∈ retrieve rs k) : r1 = r2 := by
  have m1 : r1 ∈ rs := (List.mem_filter.mp h1).1
  have m2 : r2 ∈ rs := (List.mem_filter.mp h2).1
  have a := retrieve_max rs k r1 h1 r2 m2 (retrieve_key rs k r2 h2)
  have b := retrieve_max rs k r2 h2 r1 m1 (retrieve_key rs k r1 h1)
  exact hid r1 m1 r2 m2 (by omega)

/-- a status edit (retract, explicit supersede) of record j -/
def setSt (rs : List Rec) (j : Nat) (s : St) : List Rec :=
  rs.map (fun x => if x.idx = j then { x with st := s } else x)

theorem newest_setSt (rs : List Rec) (j : Nat) (s : St) (r : Rec) :
    newest (setSt rs j s) r = newest rs r := by
  unfold newest setSt
  induction rs with
  | nil => rfl
  | cons a t ih =>
    simp only [List.map_cons, List.all_cons]
    rw [ih]
    by_cases ha : a.idx = j
    · simp [ha, newer]
    · simp [ha]

/-- no revival: editing the status of record j never changes whether another record r is current -/
theorem status_edit_no_revive (rs : List Rec) (j : Nat) (s : St) (r : Rec) :
    finalActive (setSt rs j s) r = finalActive rs r := by
  unfold finalActive
  rw [newest_setSt]

/-- the reviewed defect, in the old model: counting only ACTIVE newer records revives a predecessor -/
def finalActiveOld (rs : List Rec) (r : Rec) : Bool :=
  decide (r.st = St.active) && rs.all (fun r' => !(decide (r'.key = r.key) && decide (r'.st = St.active) && newer r' r))

theorem old_model_revives :
    let rs := [(⟨1, 10, 1, St.active⟩ : Rec), ⟨1, 20, 2, St.active⟩]
    finalActiveOld rs ⟨1, 10, 1, St.active⟩ = false ∧
    finalActiveOld (setSt rs 2 St.retracted) ⟨1, 10, 1, St.active⟩ = true := by
  decide

/-- negative control 1: with supersession disabled (mem-nosup) a superseded record is returned -/
def retrieveNoSup (rs : List Rec) (k : Nat) : List Rec := rs.filter (fun r => decide (r.key = k))

theorem nosup_returns_superseded :
    ∃ rs : List Rec, ∃ r ∈ retrieveNoSup rs 1, r.st = St.superseded :=
  ⟨[⟨1, 10, 1, St.superseded⟩, ⟨1, 20, 2, St.active⟩], ⟨1, 10, 1, St.superseded⟩, by decide, rfl⟩

/-- negative control 2: newest-per-key without the explicit status returns a retracted record -/
def retrieveNoStatus (rs : List Rec) (k : Nat) : List Rec :=
  rs.filter (fun r => decide (r.key = k) && rs.all (fun r' => !(decide (r'.key = r.key) && newer r' r)))

theorem nostatus_returns_retracted :
    ∃ rs : List Rec, ∃ r ∈ retrieveNoStatus rs 1, r.st = St.retracted :=
  ⟨[⟨1, 10, 1, St.active⟩, ⟨1, 20, 2, St.retracted⟩], ⟨1, 20, 2, St.retracted⟩, by decide, rfl⟩

end Dra146Mem

#print axioms Dra146Mem.retrieve_active
#print axioms Dra146Mem.retrieve_never_superseded
#print axioms Dra146Mem.retrieve_max
#print axioms Dra146Mem.retrieve_unique
#print axioms Dra146Mem.status_edit_no_revive
#print axioms Dra146Mem.old_model_revives
#print axioms Dra146Mem.nosup_returns_superseded
#print axioms Dra146Mem.nostatus_returns_retracted
