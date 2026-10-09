// The decoder: the instructions of a code, and the idioms among them, as a
// single automaton - NaCl's validator's way: the instructions from their
// description (spec/evm.def, made into spec/evm_insns.rl by
// tools/gen_dfa.py), the idioms (its superinstructions) by hand here,
// ragel for the automaton (ragel -x: its states and transitions),
// tools/rl2asm.py for its tables (src/evm_dfa.s), which src/decoder.s runs.
//
// The decoder runs the actions of every byte it reads; tools/verify_dfa.py
// proves that they make what the spec says (tools/evm_spec.py): every
// instruction, whatever the idioms around it, starts where the one before
// ended, ends after its immediate's bytes, and only there; an idiom is
// recognized where its last instruction ends, wherever it is and only
// there.

%%{
  machine evm_decoder;
  alphtype unsigned char;

  include evm_insns "evm_insns.rl";

  # The actions, in the order the decoder runs them where several are on
  # the same byte - the order they're defined in: an instruction starts,
  # ends, then the idioms that end with it.
  action insn_start {}
  action insn_end {}
  action static_jump {}
  action static_jumpi {}
  action selector {}
  action fmp {}

  # an instruction starts at its opcode, ends at the last byte of its
  # immediate (the opcode, without one)
  insn = instruction >insn_start @insn_end;

  # a jump to a number: where it goes is known
  static_jump = (push_any . op_jump) @static_jump;
  static_jumpi = (push_any . op_jumpi) @static_jumpi;

  # solc's dispatcher: the selector compared with a function's, the jump to
  # it if it's that one
  selector = (op_dup1 . op_push4 . op_eq . (op_push1 | op_push2 | op_push3 | op_push4) . op_jumpi) @selector;

  # solidity's free memory pointer, set first: mstore(0x40, v), v a push1
  # of 0x60 at least - where the code begins
  fmp = (0x60 . 0x60..0xff . 0x60 . 0x40 . 0x52) @fmp;

  # The instructions one after the other, the idioms recognized among them
  # (they're made of instructions: they end where one does, and the
  # instructions' actions are the ones of `insn` - the idioms have none of
  # their own but where they end). fmp? any* accepts any code: every state
  # is final - the decoder goes by the actions, never by where the
  # automaton could stop.
  main := (insn | static_jump | static_jumpi | selector)* | (fmp? . any*);
}%%

%% write data;
