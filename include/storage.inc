# The storage's structures (storage.s, storage_vars.s, storage_getter.s,
# storage_check.s): python's Storage object.

.set SG_LANG, 0                 # 1: vyper
.set SG_ACCESSES, 8             # od: (size, off, idx) -> written
.set SG_STEPS, 16               # od: (size, off, idx) -> (root, steps), sp_none for None
.set SG_TYPES, 24               # od: root -> type
.set SG_FIELDS, 32              # od: root -> [(off, end)], of a root that holds values
.set SG_LENGTHS, 40             # od: root -> the length of the fixed array there
.set SG_BG, 48                  # od: function -> (key, trace): the bytes getters
.set SG_DEFS, 56                # od: name -> (slot, off, type)
.set SG_VAR_OF, 64              # od: ('root', n) / ('field', n, off, end) -> name
.set SG_FORMS, 72               # rewrite_accesses' forms (a map), or 0
.set SG_MEMO, 80                # rewrite_accesses' walk (a map), or 0
.set SG_FORMFN, 88              # what makes the forms: 0 sg_form, 1 st_raw
.set SG_SIZEOF, 96

# checked_below's options: with the conditions of the loops (loops=True),
# of whatever x is compared with, as None (numbers=False)
.set CB_LOOPS, 1
.set CB_ANY, 2
