(*s: pfff/lang_GENERIC/parsing/Lang.mli *)
(*s: type [[Lang.t]] *)
type t = 
  | Python 
  (*s: [[Lang.t]] extra Python cases *)
  (* Python will start with Python3 mode and fall back to Python2 in case
   * of error. Python2 and Python3 are for specific version of Python 
   * (no fallback) *)
  | Python2 | Python3
  (*e: [[Lang.t]] extra Python cases *)
  | Javascript
  | Java
  | Go
  | C
  | ML
(*e: type [[Lang.t]] *)

(*s: signature [[Lang.lang_of_string_map]] *)
val lang_of_string_map: (string, t) Hashtbl.t
(*e: signature [[Lang.lang_of_string_map]] *)
(*s: signature [[Lang.lang_of_string_opt]] *)
val lang_of_string_opt: string -> t option
(*e: signature [[Lang.lang_of_string_opt]] *)

(*s: signature [[Lang.langs_of_filename]] *)
val langs_of_filename: Common.filename -> t list
(*e: signature [[Lang.langs_of_filename]] *)

(*s: signature [[Lang.files_of_dirs_or_files]] *)
val files_of_dirs_or_files: t -> Common.path list -> 
  Common.filename list
(*e: signature [[Lang.files_of_dirs_or_files]] *)

(*s: signature [[Lang.string_of_lang]] *)
val string_of_lang: t -> string
(*e: signature [[Lang.string_of_lang]] *)
(*s: signature [[Lang.ext_of_lang]] *)
val ext_of_lang: t -> string list
(*e: signature [[Lang.ext_of_lang]] *)
(*e: pfff/lang_GENERIC/parsing/Lang.mli *)
