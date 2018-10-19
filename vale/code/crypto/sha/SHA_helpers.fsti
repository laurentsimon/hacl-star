module SHA_helpers

open Prop_s
open Opaque_s
open X64.CryptoInstructions_s
open Types_s
open Words_s
open FStar.Seq
open Arch.Types

unfold
let (.[]) = FStar.Seq.index

#reset-options "--max_fuel 0 --max_ifuel 0"
  
// Specialize these definitions (from Spec.SHA2.fst) for SHA256
unfold let size_k_w = 64
val word:Type0
unfold let size_hash_w =8
(* Number of words for a block size *)
let size_block_w = 16
(* Define the size block in bytes *)
let size_block =
  let open FStar.Mul in
  4 (*size_word a*) * size_block_w
let block_w  = m:seq word {length m = size_block_w}
let counter = nat
val k0 : (s:seq word {length s = size_k_w})
unfold let hash256 = m:Seq.seq word {Seq.length m = size_hash_w}

(* Input data. *)
val byte:Type0
type bytes =  m:Seq.seq byte

(* Input data, multiple of a block length. *)
let bytes_blocks =
  l:bytes { Seq.length l % size_block = 0 }

// Hide various SHA2 definitions
val ws_opaque (b:block_w) (t:counter{t < size_k_w}): Tot (nat32)
val shuffle_core_opaque (block:block_w) (hash:hash256) (t:counter{t < size_k_w}): Tot (hash256) 
val update_multi_opaque (hash:hash256) (blocks:bytes_blocks):Tot (hash256) 

// Hide some functions that operate on words & bytes
val add_mod (x:word) (y:nat32) : nat32
val word_to_nat32 (x:word) : nat32
val nat32_to_word (x:nat32) : word
val byte_to_nat8 (b:byte) : nat8
val nat8_to_byte (b:nat8) : byte

// Work around some limitations in Vale's support for dependent types

//unfold let bytes_blocks256 = bytes_blocks SHA2_256
unfold let repeat_range_vale (max:nat { max < size_k_w}) (block:block_w) (hash:hash256) =
  Spec.Loops.repeat_range 0 max (shuffle_core_opaque block) hash
unfold let lemma_repeat_range_0_vale (block:block_w) (hash:hash256) = 
  Spec.Loops.repeat_range_base 0 (shuffle_core_opaque block) hash
unfold let update_multi_opaque_vale (hash:hash256) (blocks:bytes) : hash256 = 
  if length blocks % size_k_w = 0 then let b:bytes_blocks = blocks in update_multi_opaque hash b else hash


val make_hash (abef cdgh:quad32) : hash256
val make_ordered_hash (abef cdgh:quad32): hash256

// Top-level proof for the SHA256_rnds2 instruction
val lemma_sha256_rnds2 (abef cdgh xmm0:quad32) (t:counter) (block:block_w) (hash_in:hash256) : Lemma
  (requires t + 1 < size_k_w /\
            xmm0.lo0 == add_mod k0.[t]   (ws_opaque block t) /\
            xmm0.lo1 == add_mod k0.[t+1] (ws_opaque block (t+1)) /\ 
            make_hash abef cdgh == Spec.Loops.repeat_range 0 t (shuffle_core_opaque block) hash_in
            )
  (ensures make_hash (sha256_rnds2_spec cdgh abef xmm0) abef ==
           Spec.Loops.repeat_range 0 (t+2) (shuffle_core_opaque block) hash_in)

(* Proof work for the SHA256_msg* instructions *)
let ws_quad32 (t:counter) (block:block_w) : quad32 =
    if t < size_k_w - 3 then
       Mkfour (ws_opaque block t)
              (ws_opaque block (t+1))
              (ws_opaque block (t+2))
              (ws_opaque block (t+3))
    else 
       Mkfour 0 0 0 0

val ws_partial_def (t:counter) (block:block_w) : quad32
unfold let ws_partial = make_opaque ws_partial_def

// Top-level proof for the SHA256_msg1 instruction
val lemma_sha256_msg1 (dst src:quad32) (t:counter) (block:block_w) : Lemma
  (requires 16 <= t /\ t < size_k_w /\
            dst == ws_quad32 (t-16) block /\
            src.lo0 == ws_opaque block (t-12))
  (ensures sha256_msg1_spec dst src == ws_partial t block)

  
// Top-level proof for the SHA256_msg2 instruction
val lemma_sha256_msg2 (src1 src2:quad32) (t:counter) (block:block_w) : Lemma
  (requires 16 <= t /\ t < size_k_w - 3 /\
            (let step1 = ws_partial t block in
             let t_minus_7 = ws_quad32 (t-7) block in
             src1 == add_wrap_quad32 step1 t_minus_7 /\

             src2.hi2 == ws_opaque block (t-2) /\
             src2.hi3 == ws_opaque block (t-1)))
  (ensures sha256_msg2_spec src1 src2 == ws_quad32 t block)

open Workarounds

(* Abbreviations and lemmas for the code itself *)
let k_reqs (k_seq:seq quad32) : prop0 =
  length k_seq == size_k_w / 4 /\
  (forall i . {:pattern (index_work_around_quad32 k_seq i)} 0 <= i /\ i < (size_k_w/4) ==> 
    (k_seq.[i]).lo0 == word_to_nat32 (k0.[4 `op_Multiply` i]) /\
    (k_seq.[i]).lo1 == word_to_nat32 (k0.[4 `op_Multiply` i + 1]) /\
    (k_seq.[i]).hi2 == word_to_nat32 (k0.[4 `op_Multiply` i + 2]) /\
    (k_seq.[i]).hi3 == word_to_nat32 (k0.[4 `op_Multiply` i + 3]))
  
let quads_to_block (qs:seq quad32) : block_w
  =
  let nat32_seq = Words.Seq_s.seq_four_to_seq_LE qs in
  let f (n:nat{n < 16}) : word = nat32_to_word (if n < length nat32_seq then nat32_seq.[n] else 0) in
  init 16 f

val lemma_quads_to_block (qs:seq quad32) : Lemma
  (requires length qs == 4)
  (ensures (let block = quads_to_block qs in
            forall i . {:pattern (index_work_around_quad32 qs i)} 0 <= i /\ i < 4 ==>
              (qs.[i]).lo0 == ws_opaque block (4 `op_Multiply` i + 0) /\
              (qs.[i]).lo1 == ws_opaque block (4 `op_Multiply` i + 1) /\
              (qs.[i]).hi2 == ws_opaque block (4 `op_Multiply` i + 2) /\
              (qs.[i]).hi3 == ws_opaque block (4 `op_Multiply` i + 3) /\
              qs.[i] == ws_quad32 (4 `op_Multiply` i) block))
         
val update_block (hash:hash256) (block:block_w): hash256

val update_lemma (src1 src2 src1' src2' h0 h1:quad32) (block:block_w) : Lemma
  (requires (let hash_orig = make_hash h0 h1 in
             make_hash src1 src2 == 
             Spec.Loops.repeat_range 0 size_k_w (shuffle_core_opaque block) hash_orig /\
             src1' == add_wrap_quad32 src1 h0 /\
             src2' == add_wrap_quad32 src2 h1))
  (ensures (let hash_orig = make_hash h0 h1 in
            make_hash src1' src2' == update_block hash_orig block))

let rec update_multi_quads (s:seq quad32) (hash_orig:hash256) : Tot (hash256) (decreases (length s))
  =
  if length s < 4 then
    hash_orig
  else
    let prefix, qs = split s (length s - 4) in
    let h_prefix = update_multi_quads prefix hash_orig in
    let hash = update_block h_prefix (quads_to_block qs) in
    hash

let seq_nat8_to_seq_byte (b:seq nat8) : (b':seq byte) =
  init (length b) (fun (i:nat { i < length b }) -> let x:byte = nat8_to_byte (index b i) in x)


val lemma_update_multi_equiv_vale (hash hash':hash256) (quads:seq quad32) (r_quads:seq quad32)
  (nat8s:seq nat8) (blocks:seq byte) :
  Lemma (requires length quads % 4 == 0 /\
                  r_quads == reverse_bytes_quad32_seq quads /\
                  nat8s == le_seq_quad32_to_bytes quads /\
                  blocks == seq_nat8_to_seq_byte nat8s /\
                  hash' == update_multi_quads r_quads hash)        
        (ensures 
           length blocks % size_k_w == 0 /\
           hash' == update_multi_opaque_vale hash blocks)
        (decreases (length quads)) 

val lemma_update_multi_quads (s:seq quad32) (hash_orig:hash256) (bound:nat) : Lemma
    (requires bound + 4 <= length s)
    (ensures (let prefix_LE = slice s 0 bound in
              let prefix_BE = reverse_bytes_quad32_seq prefix_LE in
              let h_prefix = update_multi_quads prefix_BE hash_orig in
              let block_quads_LE = slice s bound (bound + 4) in
              let block_quads_BE = reverse_bytes_quad32_seq block_quads_LE in
              let input_LE = slice s 0 (bound+4) in
              let input_BE = reverse_bytes_quad32_seq input_LE in
              let h = update_block h_prefix (quads_to_block block_quads_BE) in
              h == update_multi_quads input_BE hash_orig))

let le_bytes_to_hash (b:seq nat8) : hash256 =
  if length b <> 32 then   
     (let f (n:nat{n < 8}) : word = nat32_to_word 0 in
     init 8 f)
  else (
     let open Words.Seq_s in
     Spec.Loops.seq_map nat32_to_word (seq_nat8_to_seq_nat32_LE b)
  )

val lemma_hash_to_bytes (s:seq quad32) : Lemma
  (requires length s == 2)
  (ensures make_ordered_hash s.[0] s.[1] == le_bytes_to_hash (le_seq_quad32_to_bytes s))
