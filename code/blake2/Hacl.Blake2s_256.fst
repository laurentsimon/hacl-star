module Hacl.Blake2s_256

module Spec = Spec.Blake2
module Impl = Hacl.Impl.Blake2.Generic
module Core = Hacl.Impl.Blake2.Core

[@CInline]
private
let blake2s_update_block = Impl.blake2_update_block #Spec.Blake2S #Core.M256

let blake2s = Impl.blake2 #Spec.Blake2S #Core.M256 blake2s_update_block
