(*s: pfff/h_program-lang/AST_generic.ml *)
(*s: pad/r2c copyright *)
(* Yoann Padioleau
 *
 * Copyright (C) 2019-2020 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
(*e: pad/r2c copyright *)
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* A generic AST, to factorize similar analysis in different programming
 * languages (e.g., scheck, sgrep). 
 *
 * Right now this generic AST is mostly the factorized union of:
 *  - Python
 *  - Javascript
 *  - Java
 *  - C
 *  - Go
 *  - PHP
 *  - OCaml (unfinished)
 *
 * rational: In the end, programming languages have a lot in Common.
 * Even though most interesting analysis are probably better done on a
 * per-language basis, many useful analysis are trivial and require just an
 * AST and a visitor. One could duplicate those analysis for each language
 * or design an AST (this file) generic enough to factorize all those 
 * analysis (e.g., unused entity). We want to remain
 * as precise as possible and not lose too much information while going
 * from the specific language AST to the generic AST. We also do not want
 * to be too generic as in ast_fuzzy.ml, where we have a very general 
 * tree of nodes, but all the structure of the original AST is lost.
 * 
 * todo:
 *  - add Ruby
 *  - add C++ (argh)
 *  - add Rust, Scala (difficult)
 *  - see ast_fuzzy.ml todos for ideas to use AST_generic for sgrep.
 *
 * related work:
 *  - ast_fuzzy.ml (in this directory)
 *  - github semantic
 *    https://github.com/github/semantic
 *  - UAST of babelfish
 *    https://doc.bblf.sh/uast/uast-specification-v2.html
 *  - Coverity common program representation?
 *  - Semmle internal common representation?
 *  - Infer SIL (for C++, Java, Objective-C)
 *  - Dawson Engler and Fraser Brown micro-checkers for multiple languages
 *  - Lightweight Multi-language syntax transformation paper, but does not
 *    really operate on an AST
 *  - https://tabnine.com/ which supports multiple languages, but probably
 *    again does not operate on an AST
 *  - srcML https://www.srcml.org/doc/srcMLGrammar.html
 *    but just for C/C++/C#/Java and seems pretty heavy
 *
 * design choices to have a generic data structure:
 *  - add some 'a, 'b, 'c around expr/stmt/...
 *  - data-type a la carte like in github-semantic but IMHO too high-level
 *    with astronaut-style architecture (too abstract, too advanced features).
 *  - the OtherXxx strategy used in this file (simple)
 *  - functorize and add some type hole (type tstmt; type texpr; ...),
 *    todo? not a bad idea if later we want to add type information on each
 *    expression nodes
 *
 * history:
 *  - started with crossproduct of Javascript, Python, PHP, Java, and C
 *    (and a bit of OCaml) after wanting to port checked_return from Js to
 *    Python and got the idea to factorize things
 *
 * INVARIANTS:
 *  - all the other_xxx types should contain only simple constructors (enums)
 *    without any parameter. I rely on that to simplify the code 
 *    of the generic mapper and matcher.
 *    Same for keyword_attribute.
 *  - each expression or statement must have at least one token in it
 *    so that sgrep can report correctly ranges (e.g., 'Return of expr option'
 *    is not enough because with no expr, there is no location information
 *    for this return, so it must be 'Return of tok * expr option' instead)
 *  - to correctly compute a CFG (Control Flow Graph), the stmt type 
 *    should list all constructs that contains other statements and 
 *    try to avoid to use the very generic OtherXxx of any
 *  - to correctly compute a DFG (Data Flow Graph), and to correctly resolve
 *    names (see Naming_AST.ml), each constructs that introduce a new
*     variable should have a relevant comment 'newvar:'
 *  - to correctly resolve names, each constructs that introduce a new scope
 *    should have a relevant comment 'newscope:'
 *  - todo? each language should add the VarDefs that defines the locals
 *    used in a function (instead of having the first Assign play the role
 *    of a VarDef, as done in Python for example).
 *
 * See also pfff/lang_GENERIC/
 *)

(*****************************************************************************)
(* Token (leaf) *)
(*****************************************************************************)

(*s: type [[AST_generic.tok]] *)
(* Contains among other things the position of the token through
 * the Parse_info.token_location embedded inside it, as well as the
 * transformation field that makes possible spatch on the code.
 *)
type tok = Parse_info.t
(*e: type [[AST_generic.tok]] *)
 (* with tarzan *)

(*s: type [[AST_generic.wrap]] *)
(* a shortcut to annotate some information with position information *)
type 'a wrap = 'a * tok
(*e: type [[AST_generic.wrap]] *)
 (* with tarzan *)

(*s: type [[AST_generic.bracket]] *)
(* Use for round(), square[], curly{}, and angle<> brackets. 
 * note: in theory we should not care about those tokens in an AST, 
 * but they are useful to report correct ranges in sgrep when we match
 * something that can just be those brackets (e.g., an empty container).
 *)
type 'a bracket = tok * 'a * tok
(*e: type [[AST_generic.bracket]] *)
 (* with tarzan *)

(*****************************************************************************)
(* Names *)
(*****************************************************************************)

(*s: type [[AST_generic.ident]] *)
type ident = string wrap
(*e: type [[AST_generic.ident]] *)

(*s: type [[AST_generic.dotted_ident]] *)
type dotted_ident = ident list (* at least 1 element *)
(*e: type [[AST_generic.dotted_ident]] *)
 (* with tarzan *)

(*s: type [[AST_generic.module_name]] *)
(* module_name can also be used for a package name or a namespace *)
type module_name =
  | DottedName of dotted_ident (* ex: Python *)
  (* in FileName the '/' is similar to the '.' in DottedName *)
  | FileName of string wrap   (* ex: Js import, C #include, Go import *)
(*e: type [[AST_generic.module_name]] *)
 (* with tarzan *)

(* A single unique id: sid (uid would be a better name, but it usually 
 * means "user id" for people).
 *
 * This single id simplifies further analysis which need less to care about 
 * maintaining scoping information, for example to deal with variable
 * shadowing, or functions using the same parameter names 
 * (even though you still need to handle specially recursive functions), etc.
 *
 * See Naming_AST.ml for more information. 
 * 
 * Most generic ASTs have a fake value (sid_TODO = -1) at first. 
 * You need to call Naming_AST.resolve (or one of the lang-specific
 * Resolve_xxx.resolve) on the generic AST to set it correctly.
 *)
(*s: type [[AST_generic.sid]] *)
type sid = int (* a single unique gensym'ed number. See gensym() below *)
(*e: type [[AST_generic.sid]] *)

(*s: type [[AST_generic.resolved_name]] *)
and resolved_name = resolved_name_kind * sid
(*e: type [[AST_generic.resolved_name]] *)
(*s: type [[AST_generic.resolved_name_kind]] *)
  and resolved_name_kind =
  (* Global is useful in codemap/efuns to highlight differently and warn
   * about the use of globals inside functions.
   * old: Global was merged with ImportedEntity before but simpler to split, as
   * anyway I was putting often an empty list for dotted_ident with a 
   * todo note in the code.
   *)
  | Global 
  (* Those could be merged, but again this is useful in codemap/efuns *)
  | Local | Param 
  (* For closures; can refer to a Local or Param.
   * With sid this is potentially less useful for scoping-related issues,
   * but this can be useful in codemap to again highlight specially 
   * enclosed vars.
   *)
  | EnclosedVar (* less: add depth? *)

  (* sgrep: those cases allow to match entities/modules even if they were
   * aliased when imported.
   * both dotted_ident must at least contain one element *)
  | ImportedEntity of dotted_ident (* can also use 0 for gensym *)
  | ImportedModule of module_name

  (* used in Go, where you can pass types as arguments and where we
   * need to resolve those cases
   *)
  | TypeName 
  (* used for C *)
  | Macro
  | EnumConstant
(*e: type [[AST_generic.resolved_name_kind]] *)

 (* with tarzan *)

(* Start of big mutually recursive types because of the use of 'any' 
 * in OtherXxx *)

(*s: type [[AST_generic.name]] *)
type name = ident * name_info
(*e: type [[AST_generic.name]] *)
(*s: type [[AST_generic.name_info]] *)
  and name_info = { 
    name_qualifier: qualifier option;
    name_typeargs: type_arguments option; (* Java *)
  } 
  (* todo: not enough in OCaml with functor and type args or C++ templates*)
(*e: type [[AST_generic.name_info]] *)
(*s: type [[AST_generic.qualifier]] *)
  and qualifier = dotted_ident
(*e: type [[AST_generic.qualifier]] *)

(*****************************************************************************)
(* Naming/typing *)
(*****************************************************************************)

(*s: type [[AST_generic.id_info]] *)
and id_info = {
    id_resolved: resolved_name option ref; (* variable tagger (naming) *)
    id_type:     type_         option ref; (* type checker (typing) *)
    (* sgrep: this is for sgrep constant propagation hack.
     * todo? associate only with Id?
     *)
    id_const_literal: literal option ref;
  }
(*e: type [[AST_generic.id_info]] *)

(*****************************************************************************)
(* Expression *)
(*****************************************************************************)

(*s: type [[AST_generic.expr]] *)
and expr = 
  (* basic (atomic) values *)
  | L of literal

  (* composite values *)
  | Container of container_operator * expr list bracket
  (*s: [[AST_generic.expr]] other composite cases *)
  (* special case of Container, at least 2 elements *) 
  | Tuple of expr list 
  (*x: [[AST_generic.expr]] other composite cases *)
  (* And-type (field.vinit should be a Some) *)
  | Record of field list bracket
  (*x: [[AST_generic.expr]] other composite cases *)
  (* Or-type (could be used instead of Container, Cons, Nil, etc.) *)
  | Constructor of name * expr list
  (* see also Call(IdSpecial (New,_), [ArgType _;...] for other values *)
  (*e: [[AST_generic.expr]] other composite cases *)

  | Id of ident * id_info
  (*s: [[AST_generic.expr]] other identifier cases *)
  (* old: Id above used to be called Name and was generalizing also IdQualified
   * but some analysis are easier when they just need to
   * handle a simple Id, hence the split. For example, there was some bugs
   * in sgrep because sometimes an identifier was an ident (in function header)
   * and sometimes a name (when called). For naming, we also need to do
   * things differently for Id vs IdQualified and would need many times to
   * inspect the name.name_qualifier to know if we have an Id or IdQualified.
   * We do the same split for Fid vs FName for fields.
   * 
   * newvar: Id is sometimes abused to also introduce a newvar (as in Python)
   * but ultimately those cases should be rewritten to first introduce 
   * a VarDef. 
   *)
  (* todo: Sometimes some DotAccess should really be transformed in IdQualified
   * with a better qualifier because the obj is actually the name of a package
   * or module, but you may need advanced semantic information and global
   * analysis to disambiguate.
   *)
  | IdQualified of name * id_info
  (*x: [[AST_generic.expr]] other identifier cases *)
  | IdSpecial of special wrap
  (*e: [[AST_generic.expr]] other identifier cases *)

  (* operators and function application *)
  | Call of expr * arguments
  (*s: [[AST_generic.expr]] other call cases *)
  (* (XHP, JSX, TSX), could be transpiled also (done in IL.ml?) *)
  | Xml of xml
  (* IntepolatedString of expr list is simulated with a 
   * Call(IdSpecial (Concat ...)) *)
  (*e: [[AST_generic.expr]] other call cases *)

  (* The left part should be an lvalue (Id, DotAccess, ArrayAccess, Deref)
   * but it can also be a pattern (Tuple, Container, even Record), but
   * you should really use LetPattern for that.
   * Assign can also be abused to declare new variables, but you should use
   * variable_definition for that.
   * less: should be in stmt, but most languages allow this at expr level :(
   * todo: see IL.ml where we normalize this AST with expr/instr/stmt
   * update: should even be in a separate simple_stmt, as in Go
   *)
  | Assign of expr * tok (* =, or sometimes := in Go, <- in OCaml *) * expr
  (*s: [[AST_generic.expr]] other assign cases *)
  (* less: could desugar in Assign, should be only binary_operator *)
  | AssignOp of expr * arithmetic_operator wrap * expr
  (* newvar:! newscope:? in OCaml yes but we miss the 'in' part here  *)
  | LetPattern of pattern * expr
  (*e: [[AST_generic.expr]] other assign cases *)

  (* can be used for Record, Class, or Module access depending on expr.
   * In the last case it should be rewritten as a IdQualified with a
   * qualifier though.
   *)
  | DotAccess of expr * tok (* ., ::, ->, # *) * field_ident 

  (*s: [[AST_generic.expr]] array access cases *)
  (* in Js ArrayAccess is also abused to perform DotAccess (..., FDynamic) *)
  | ArrayAccess of expr * expr
  (*x: [[AST_generic.expr]] array access cases *)
  (* could also use ArrayAccess with a Tuple rhs, or use a special *)
  | SliceAccess of expr * 
      expr option (* lower *) * expr option (* upper *) * expr option (* step*)
  (*e: [[AST_generic.expr]] array access cases *)
  (*s: [[AST_generic.expr]] anonymous entity cases *)
  (* very special value *)
  | Lambda of function_definition
  (* usually an argument of a New (used in Java, Javascript) *)
  | AnonClass of class_definition
  (*e: [[AST_generic.expr]] anonymous entity cases *)
  (*s: [[AST_generic.expr]] other cases *)
  (* a.k.a ternary expression, or regular if in OCaml *)
  | Conditional of expr * expr * expr 
  | MatchPattern of expr * action list
  (* less: TryFunctional *)

  | Yield of tok * expr option * bool (* 'from' for Python *)
  | Await of tok * expr
  (* Send/Recv of Go are currently in OtherExpr *)

  | Cast of type_ * expr
  (* less: should be in statement *)
  | Seq of expr list (* at least 2 elements *)

  (* less: could be in Special, but pretty important so I've lifted them here*)
  | Ref   of tok (* &, address of *) * expr 
  | DeRef of tok (* '*' in C, '!' or '<-' in OCaml, ^ in Reason *) * expr 
  (*e: [[AST_generic.expr]] other cases *)

  (*s: [[AST_generic.expr]] semgrep extensions cases *)
  (* sgrep: ... in expressions, args, stmts, items, and fields
   * (and unfortunately also in types in Python) *)
  | Ellipsis of tok (* '...' *)
  (*x: [[AST_generic.expr]] semgrep extensions cases *)
  | DeepEllipsis of expr bracket (* <... ...> *)
  (*x: [[AST_generic.expr]] semgrep extensions cases *)
  | DisjExpr of expr * expr
  (*x: [[AST_generic.expr]] semgrep extensions cases *)
  | TypedMetavar of ident * tok (* : *) * type_
  (*e: [[AST_generic.expr]] semgrep extensions cases *)
  (*s: [[AST_generic.expr]] OtherXxx case *)
  (* TODO: other_expr_operator wrap, so enforce at least one token instead
   * of relying that the any list contains at least one token *)
  | OtherExpr of other_expr_operator * any list
  (*e: [[AST_generic.expr]] OtherXxx case *)
(*e: type [[AST_generic.expr]] *)

(*s: type [[AST_generic.literal]] *)
  and literal = 
    | Bool of bool wrap
    | Int of string wrap | Float of string wrap
    | Char of string wrap | String of string wrap | Regexp of string wrap
    | Unit of tok (* a.k.a Void *) | Null of tok | Undefined of tok (* JS *)
    | Imag of string wrap (* Go, Python *)
(*e: type [[AST_generic.literal]] *)

(*s: type [[AST_generic.container_operator]] *)
  and container_operator = 
    (* Tuple was lifted up *)
    | Array (* todo? designator? use ArrayAccess for designator? *)
    | List | Set
    | Dict (* a.k.a Hash or Map (combine with Tuple to get Key/value pair) *)
(*e: type [[AST_generic.container_operator]] *)

  (* It's useful to keep track in the AST of all those special identifiers.
   * They need to be handled in a special way by certain analysis and just
   * using Name for them would be error-prone.
   * Note though that by putting all of them together in a type, we lose
   * typing information, for example Eval takes only one argument and
   * InstanceOf takes a type and an expr. This is a tradeoff to also not 
   * polluate too much expr with too many constructs.
   *)
(*s: type [[AST_generic.special]] *)
  and special = 
   (* special vars *)
   | This | Super
   | Self | Parent (* different from This/Super? *)

   (* special calls *)
   | Eval
   | Typeof (* for C? and Go in switch x.(type) *)
   | Instanceof | Sizeof (* takes a ArgType *)
   (* note that certain languages do not have a 'new' keyword 
    * (e.g., Python, Scala 3), instead certain 'Call' are really 'New' *)
   | New  (* usually associated with Call(New, [ArgType _;...]) *)

   (* used for interpolated strings constructs *)
   | ConcatString of concat_string_kind
   | EncodedString of string wrap (* only for Python for now (e.g., b"foo") *)
   (* TaggedString? for Javascript, for styled.div`bla{xx}`?
    * We could have this TaggedString where the first arg of Call
    * will be the tagging function, and the rest will be a Call ConcatString. 
    * However, it is simpler to just transform those special calls as
    * regular calls even though they do not have parenthesis
    * (not all calls have parenthesis anyway, as in OCaml or Ruby).
    *)
   | Spread (* inline list var, in Container or call context *)

   (* used for unary and binary operations *)
   | ArithOp of arithmetic_operator
   (* less: should be lift up and transformed in Assign at stmt level *)
   | IncrDecr of (incr_decr * prefix_postfix)
(*e: type [[AST_generic.special]] *)

    (* mostly binary operators.
     * less: could be divided in really Arith vs Logical (bool) operators,
     * but see is_boolean_operator() helper below.
     * Note that Mod can be used for %style string formatting in Python.
     * Note that Plus can also be used for string concatenations in Go/??.
     * todo? use a Special operator intead for that? but need type info?
     *)
(*s: type [[AST_generic.arithmetic_operator]] *)
    and arithmetic_operator = 
      | Plus (* unary too *) | Minus (* unary too *) 
      | Mult | Div | Mod
      | Pow | FloorDiv | MatMult (* Python *)
      | LSL | LSR | ASR (* L = logic, A = Arithmetic, SL = shift left *) 
      | BitOr | BitXor | BitAnd | BitNot (* unary *) | BitClear (* Go *)
      (* todo? rewrite in CondExpr? have special behavior *)
      | And | Or (* also shortcut operator *) | Xor (* PHP*) | Not (* unary *)
      | Eq (* '=' in OCaml, '==' in Go/... *)
      | NotEq     (* less: could be desugared to Not Eq *)
      | PhysEq (* '==' in OCaml, '===' in JS/... *)
      | NotPhysEq (* less: could be desugared to Not PhysEq *)
      | Lt | LtE | Gt | GtE  (* less: could be desugared to Or (Eq Lt) *)
      | Cmp (* <=>, PHP *)
      (* todo: not really an arithmetic operator, maybe rename the type *)
      | Concat (* '.' PHP *)
(*e: type [[AST_generic.arithmetic_operator]] *)
(*s: type [[AST_generic.incr_decr]] *)
    and incr_decr = Incr | Decr (* '++', '--' *)
(*e: type [[AST_generic.incr_decr]] *)
(*s: type [[AST_generic.prefix_postfix]] *)
    and prefix_postfix = Prefix | Postfix
(*e: type [[AST_generic.prefix_postfix]] *)
   and concat_string_kind = 
     (* many languages do not require a special syntax to use interpolated
      * strings e.g. simply "this is {a}". Javascript uses backquotes.
      *)
     | InterpolatedConcat (* Javascript/PHP/Ruby/Perl *)
     (* many languages have a binary Concat operator to concatenate strings,
      * but some languages also allow the simple juxtaposition of multiple
      * strings to be concatenated, e.g. "hello" "world" in Python.
      *)
     | SequenceConcat (* Python/C *)
     (* Python requires the special f"" syntax to use interpolated strings,
      * and some semgrep users may want to explicitely match only f-strings,
      * which is why we record this information here.
      *)
     | FString (* Python *)

(*s: type [[AST_generic.field_ident]] *)
  and field_ident =
    | FId of ident (* hard to put '* id_info' here, hard to resolve *)
    (*s: [[AST_generic.field_ident]] other cases *)
    | FName of name (* OCaml *)
    | FDynamic of expr (* PHP, JS (even though use ArrayAccess for that) *)
    (*e: [[AST_generic.field_ident]] other cases *)
(*e: type [[AST_generic.field_ident]] *)


  (* newscope: newvar: *)
(*s: type [[AST_generic.action]] *)
  and action = pattern * expr
(*e: type [[AST_generic.action]] *)

    (* less: could make it more generic by adding a 'expr so it could be
     * reused in ast_js.ml, ast_php.ml
     *)
(*s: type [[AST_generic.xml]] *)
    and xml = {
      xml_tag: ident;
      xml_attrs: xml_attribute list;
      xml_body: xml_body list;
    }
(*e: type [[AST_generic.xml]] *)
(*s: type [[AST_generic.xml_attribute]] *)
     and xml_attribute = ident * xml_attr_value
(*e: type [[AST_generic.xml_attribute]] *)
(*s: type [[AST_generic.xml_attr_value]] *)
       and xml_attr_value = expr
(*e: type [[AST_generic.xml_attr_value]] *)
(*s: type [[AST_generic.xml_body]] *)
     and xml_body =
      | XmlText of string wrap
      | XmlExpr of expr
      | XmlXml of xml
(*e: type [[AST_generic.xml_body]] *)

(*s: type [[AST_generic.arguments]] *)
  and arguments = argument list (* bracket? not in OCaml/Ruby *)
(*e: type [[AST_generic.arguments]] *)
(*s: type [[AST_generic.argument]] *)
    and argument =
      (* regular argument *)
      | Arg of expr (* can be Call (IdSpecial Spread, Id foo) *)
      (*s: [[AST_generic.argument]] other cases *)
      (* keyword argument *)
      | ArgKwd of ident * expr
      (*x: [[AST_generic.argument]] other cases *)
      (* type argument for New, instanceof/sizeof/typeof, C macros *)
      | ArgType of type_
      (*e: [[AST_generic.argument]] other cases *)
      (*s: [[AST_generic.argument]] OtherXxx case *)
      | ArgOther of other_argument_operator * any list
      (*e: [[AST_generic.argument]] OtherXxx case *)

(*e: type [[AST_generic.argument]] *)

(*s: type [[AST_generic.other_argument_operator]] *)
       and other_argument_operator =
        (* Python *)
        | OA_ArgPow (* a kind of Spread, but for Dict instead of List *)
        | OA_ArgComp (* comprehension *)
        (* OCaml *)
        | OA_ArgQuestion
(*e: type [[AST_generic.other_argument_operator]] *)

  (* todo: reduce, or move in other_special? *)
(*s: type [[AST_generic.other_expr_operator]] *)
  and other_expr_operator = 
    (* Javascript *)
    | OE_Exports | OE_Module 
    | OE_Define | OE_Arguments 
    | OE_NewTarget
    | OE_Delete | OE_YieldStar
    | OE_Require (* todo: lift to DirectiveStmt? transform in Import? *) 
    | OE_UseStrict (* todo: lift up to program attribute/directive? *)
    (* Python *)
    | OE_In | OE_NotIn (* less: could be part of a obj_operator? *)
    | OE_Invert
    | OE_Slices (* see also SliceAccess *)
    (* todo: newvar: *)
    | OE_CompForIf | OE_CompFor | OE_CompIf
    | OE_CmpOps
    | OE_Repr (* todo: move to special, special Dump *)
    (* Java *)
    | OE_NameOrClassType | OE_ClassLiteral | OE_NewQualifiedClass
    | OE_Annot
    (* C *)
    | OE_GetRefLabel
    | OE_ArrayInitDesignator (* [x] = ... todo? use ArrayAccess in container?*)
    (* PHP *)
    | OE_Unpack
    (* OCaml *)
    | OE_RecordWith | OE_RecordFieldName
    | OE_StmtExpr (* OCaml has just expressions, no statements *)
    (* Go *)
    | OE_Send | OE_Recv
(*e: type [[AST_generic.other_expr_operator]] *)

(*****************************************************************************)
(* Statement *)
(*****************************************************************************)
(*s: type [[AST_generic.stmt]] *)
and stmt =
  (* See also IL.ml where Call/Assign/Seq are not in expr and where there are
   * separate expr, instr, and stmt types *)
  | ExprStmt of expr

  (* newscope: in C++/Java/Go *)
  | Block of stmt list (* todo: bracket *)
  (* EmptyStmt = Block [], or separate so can not be matched by $S? $ *)

  (* newscope: for vardef in expr in C++/Go/... *)
  | If of tok (* 'if' or 'elif' *) * expr * stmt * stmt option
  | While   of tok * expr * stmt

  | Return   of tok * expr option
  (*s: [[AST_generic.stmt]] other cases *)
  | DoWhile of tok * stmt * expr
  (* newscope: *)
  | For of tok (* 'for', 'foreach'*) * for_header * stmt

  (* The expr can be None for Go.
   * less: could be merged with ExprStmt (MatchPattern ...) *)
  | Switch of tok (* 'switch' or also 'select' in Go *) * expr option * 
     case_and_body list

  | Continue of tok * label_ident
  | Break    of tok * label_ident

  | Label of label * stmt
  | Goto of tok * label

  | Throw of tok (* 'raise' in OCaml, 'throw' in Java/PHP *) * expr
  | Try of tok * stmt * catch list * finally option
  | Assert of tok * expr * expr option (* message *)
  (*e: [[AST_generic.stmt]] other cases *)
  (*s: [[AST_generic.stmt]] toplevel and nested construct cases *)
  | DefStmt of definition
  (*x: [[AST_generic.stmt]] toplevel and nested construct cases *)
  | DirectiveStmt of directive
  (*e: [[AST_generic.stmt]] toplevel and nested construct cases *)
  (*s: [[AST_generic.stmt]] semgrep extensions cases *)
  (* sgrep: *)
  | DisjStmt of stmt * stmt
  (*e: [[AST_generic.stmt]] semgrep extensions cases *)
  (*s: [[AST_generic.stmt]] OtherXxx case *)
  (* this is important to correctly compute a CFG *)
  | OtherStmtWithStmt of other_stmt_with_stmt_operator * expr * stmt
  (* any here should not contain any statement! otherwise the CFG will be
   * incorrect and some analysis (e.g., liveness) will be incorrect.
   * TODO: other_stmt_operator wrap, so enforce at least one token instead
   * of relying that the any list contains at least one token
   *)
  | OtherStmt of other_stmt_operator * any list
  (*e: [[AST_generic.stmt]] OtherXxx case *)
(*e: type [[AST_generic.stmt]] *)

  (* newscope: *)
  (* less: could merge even more with pattern
   * list = PatDisj and Default = PatUnderscore, 
   * so case_and_body of Switch <=> action of MatchPattern
   *)
(*s: type [[AST_generic.case_and_body]] *)
  and case_and_body = case list * stmt
(*e: type [[AST_generic.case_and_body]] *)
(*s: type [[AST_generic.case]] *)
    and case  =
    | Case    of tok * pattern
    | Default of tok
    (* For Go, expr can contain some Assign bindings. 
     * todo? could merge with regular Case? can 'case x := <-chan' be
     * transformed in a pattern?
     *)
    | CaseEqualExpr of tok * expr
(*e: type [[AST_generic.case]] *)

  (* newvar: newscope: usually a PatVar *)
(*s: type [[AST_generic.catch]] *)
  and catch = tok (* 'catch', 'except' in Python *) * pattern * stmt
  (* newscope: *)
(*e: type [[AST_generic.catch]] *)
(*s: type [[AST_generic.finally]] *)
  and finally = tok (* 'finally' *) * stmt
(*e: type [[AST_generic.finally]] *)

(*s: type [[AST_generic.label]] *)
  and label = ident
(*e: type [[AST_generic.label]] *)
(*s: type [[AST_generic.label_ident]] *)
  and label_ident =
    | LNone (* C/Python *)
    | LId of label (* Java/Go *)
    | LInt of int wrap (* PHP *)
    | LDynamic of expr (* PHP, woohoo, dynamic break! bailout for CFG *)
(*e: type [[AST_generic.label_ident]] *)

(*s: type [[AST_generic.for_header]] *)
  and for_header = 
    (* todo? copy Go and have instead   
     * ForClassic of simple option * expr * simple option?
     *)
    | ForClassic of for_var_or_expr list (* init *) * 
                    expr option (* cond *) * 
                    expr option (* next *)
    (* newvar: *)
    | ForEach of pattern * 
                 tok (* 'in' Python, 'range' Go, 'as' PHP, '' Java *) * 
                 expr (* pattern 'in' expr *)
(*e: type [[AST_generic.for_header]] *)

(*s: type [[AST_generic.for_var_or_expr]] *)
    and for_var_or_expr = 
    (* newvar: *)
    | ForInitVar of entity * variable_definition
    | ForInitExpr of expr
(*e: type [[AST_generic.for_var_or_expr]] *)

(*s: type [[AST_generic.other_stmt_with_stmt_operator]] *)
  and other_stmt_with_stmt_operator = 
    (* Python *)
    | OSWS_With (* newscope: newvar: in OtherStmtWithStmt with LetPattern *)
(*e: type [[AST_generic.other_stmt_with_stmt_operator]] *)

(*s: type [[AST_generic.other_stmt_operator]] *)
  and other_stmt_operator = 
    (* Python *)
    | OS_Delete 
    (* todo: reduce? transpile? *)
    | OS_ForOrElse | OS_WhileOrElse | OS_TryOrElse
    | OS_ThrowFrom | OS_ThrowNothing 
    | OS_Pass
    | OS_Async
    (* Java *)
    | OS_Sync
    (* C *)
    | OS_Asm
    (* Go *)
    | OS_Go | OS_Defer 
    | OS_Fallthrough (* only in Switch *)
    (* PHP *)
    | OS_GlobalComplex (* e.g., global $$x, argh *)
(*e: type [[AST_generic.other_stmt_operator]] *)

(*****************************************************************************)
(* Pattern *)
(*****************************************************************************)
(* This is quite similar to expr. A few constructs in expr have
 * equivalent here prefixed with Pat (e.g., PaLiteral, PatId). We could
 * maybe factorize with expr, and this may help sgrep, but I think it's
 * cleaner to have a separate type because the scoping rules for a pattern and
 * an expr are quite different and not any expr is allowed here.
 *)
(*s: type [[AST_generic.pattern]] *)
and pattern = 
  | PatLiteral of literal
  (* Or-Type, used also to match OCaml exceptions *)
  | PatConstructor of name * pattern list
  (* And-Type*)
  | PatRecord of (name * pattern) list bracket

  (* newvar:! *)
  | PatId of ident * id_info (* Usually Local/Param, Global in toplevel let *)

  (* special cases of PatConstructor *)
  | PatTuple of pattern list (* at least 2 elements *)
  (* less: generalize to other container_operator? *)
  | PatList of pattern list bracket
  | PatKeyVal of pattern * pattern (* a kind of PatTuple *)

  (* special case of PatId *)
  | PatUnderscore of tok

  (* OCaml *)
  | PatDisj  of pattern * pattern (* also abused for catch in Java *)
  | PatTyped of pattern * type_
  | PatWhen  of pattern * expr
  | PatAs    of pattern * (ident * id_info)

  (* For Go also in switch x.(type) { case int: ... } *)
  | PatType of type_
  (* In catch for Java/PHP, and foreach in Java.
   * less: do instead PatAs (PatType(TyApply, var))?
   *       or even    PatAs (PatConstructor(id, []), var)?
   *)
  | PatVar of type_ * (ident * id_info) option

  (*s: [[AST_generic.pattern]] semgrep extensions cases *)
  (* sgrep: *)
  | DisjPat of pattern * pattern
  (*e: [[AST_generic.pattern]] semgrep extensions cases *)

  | OtherPat of other_pattern_operator * any list
(*e: type [[AST_generic.pattern]] *)

(*s: type [[AST_generic.other_pattern_operator]] *)
  and other_pattern_operator =
  (* Python *)
  | OP_Expr (* todo: should transform via expr_to_pattern() below *)
(*e: type [[AST_generic.other_pattern_operator]] *)

(*****************************************************************************)
(* Type *)
(*****************************************************************************)

(*s: type [[AST_generic.type_]] *)
and type_ =
  (* todo? a type_builtin = TInt | TBool | ...? see Literal *)
  | TyBuiltin of string wrap (* int, bool, etc. could be TApply with no args *)
 
  (* old: was 'type_ list * type*' , but languages such as C and 
   * Go allow also to name those parameters, and Go even allow Variadic 
   * parameters so we need at least 'type_ * attributes', at which point 
   * it's better to just use parameter_classic
   *)
  | TyFun of parameter_classic list * type_ (* return type *)

  (* a special case of TApply, also a special case of TPointer *)
  | TyArray of (* const_expr *) expr option * type_
  | TyTuple of type_ list bracket (* at least 2 elements *)

  (*s: [[AST_generic.type_]] other cases *)
   (* old: was originally TyApply (name, []), but better to differentiate.
    * todo? may need also TySpecial because the name can actually be
    *  self/parent/static (e.g., in PHP)
    * todo? maybe go even further and differentiate TyId vs TyIdQualified?
    *)
  | TyName of name
  (* covers tuples, list, etc.*)
  | TyNameApply of name * type_arguments

  | TyVar of ident (* type variable in polymorphic types (not a typedef) *)

  | TyPointer of tok * type_ (* | TODO TyRef of tok * type_ for C++ *)

  | TyQuestion of type_ * tok (* a.k.a option type *)

  (* Anonymous record type, a.k.a shape in PHP/Hack. See also AndType.
   * Most record types are defined via a TypeDef and are then referenced
   * via a TyName. Here we have flexible record types (a.k.a. rows in OCaml).
   *)
  | TyAnd of (ident * type_) list bracket
  (* unused for now, but could use for OCaml variants, or for union types! *)
  | TyOr of type_ list
  (*e: [[AST_generic.type_]] other cases *)
  (*s: [[AST_generic.type_]] OtherXxx case *)
  | OtherType of other_type_operator * any list
  (*e: [[AST_generic.type_]] OtherXxx case *)
(*e: type [[AST_generic.type_]] *)
  
(*s: type [[AST_generic.type_arguments]] *)
  and type_arguments = type_argument list
(*e: type [[AST_generic.type_arguments]] *)

(*s: type [[AST_generic.type_argument]] *)
    and type_argument = 
      | TypeArg of type_

      | OtherTypeArg of other_type_argument_operator * any list
(*e: type [[AST_generic.type_argument]] *)

(*s: type [[AST_generic.other_type_argument_operator]] *)
      and other_type_argument_operator =
       | OTA_Question
(*e: type [[AST_generic.other_type_argument_operator]] *)

(*s: type [[AST_generic.other_type_operator]] *)
  and other_type_operator = 
  (* Python *)
  | OT_Expr | OT_Arg (* todo: should use expr_to_type() below when can *)
  (* C *)
  (* todo? convert in unique names with TyName? *)
  | OT_StructName | OT_UnionName | OT_EnumName 
  (* PHP *)
  | OT_ShapeComplex (* complex TyAnd with complex keys *) 
  | OT_Variadic (* ???? *)
(*e: type [[AST_generic.other_type_operator]] *)

(*****************************************************************************)
(* Attribute *)
(*****************************************************************************)
(* a.k.a decorators, annotations *)
(*s: type [[AST_generic.attribute]] *)
and attribute = 
  | KeywordAttr of keyword_attribute wrap
  (* for general @annotations *)
  | NamedAttr of ident * id_info * argument list
  (*s: [[AST_generic.attribute]] OtherXxx case *)
  | OtherAttribute of other_attribute_operator * any list
  (*e: [[AST_generic.attribute]] OtherXxx case *)
(*e: type [[AST_generic.attribute]] *)

(*s: type [[AST_generic.keyword_attribute]] *)
  and keyword_attribute =
  | Static | Volatile | Extern
  (* for class fields *)
  | Public | Private | Protected
  | Abstract | Final
  (* for vars (JS) *)
  | Var | Let
  (* for fields *)
  | Mutable | Const
  (* for functions *)
  | Generator | Async 
  | Recursive | MutuallyRecursive
  (* for methods *)
  | Ctor | Dtor
  | Getter | Setter
  (* for parameters *)
  | Variadic
(*e: type [[AST_generic.keyword_attribute]] *)

(*s: type [[AST_generic.other_attribute_operator]] *)
  and other_attribute_operator = 
    (* Java *)
    | OA_StrictFP | OA_Transient | OA_Synchronized | OA_Native
    | OA_AnnotJavaOther
    | OA_AnnotThrow
    (* Python *)
    | OA_Expr (* todo: should transform in NamedAttr when can *)
(*e: type [[AST_generic.other_attribute_operator]] *)

(*****************************************************************************)
(* Definitions *)
(*****************************************************************************)
(* definition (or just declaration sometimes) *)
(*s: type [[AST_generic.definition]] *)
and definition = entity * definition_kind
(*e: type [[AST_generic.definition]] *)

(* old: type_: type_ option; but redundant with the type information in
 * the different definition_kind, as well as in id_info, and does not
 * have any meanings for certain defs (e.g., ClassDef) so not worth
 * factoring.
 *
 * see special_multivardef_pattern below for many vardefs in one entity in
 * ident.
 *)
(*s: type [[AST_generic.entity]] *)
  and entity = {
    name: ident;
    (*s: [[AST_generic.entity]] attribute field *)
    attrs: attribute list;
    (*e: [[AST_generic.entity]] attribute field *)
    (*s: [[AST_generic.entity]] id info field *)
    (* naming/typing *)
    info: id_info;
    (*e: [[AST_generic.entity]] id info field *)
    (*s: [[AST_generic.entity]] other fields *)
    tparams: type_parameter list;
    (*e: [[AST_generic.entity]] other fields *)
  }
(*e: type [[AST_generic.entity]] *)

(*s: type [[AST_generic.definition_kind]] *)
  and definition_kind =
    (* newvar: can be used also for methods, nested functions, lambdas.
     * note: can have empty "body" when the def is actually a declaration
     * in a header file (called a prototype in C).
     *)
    | FuncDef   of function_definition
    (* newvar: can be used also for constants, fields.
     * can contain special_multivardef_pattern ident in which case vinit
     * is the pattern assignment.
     *)
    | VarDef    of variable_definition
    | ClassDef  of class_definition
    (*s: [[AST_generic.definition_kind]] other cases *)
    | TypeDef   of type_definition

    | ModuleDef of module_definition
    | MacroDef of macro_definition
    (*x: [[AST_generic.definition_kind]] other cases *)
    (* in a header file (e.g., .mli in OCaml or 'module sig') *)
    | Signature of type_
    (*x: [[AST_generic.definition_kind]] other cases *)
    (* Only used inside a function.
     * Needed for languages without local VarDef (e.g., Python/PHP)
     * where the first use is also its declaration. In that case when we
     * want to access a global we need to disambiguate with creating a new
     * local.
     *)
    | UseOuterDecl of tok (* 'global' or 'nonlocal' in Python, 'use' in PHP *)
    (*e: [[AST_generic.definition_kind]] other cases *)
(*e: type [[AST_generic.definition_kind]] *)

(* template/generics/polymorphic-type *)
(*s: type [[AST_generic.type_parameter]] *)
and type_parameter = ident * type_parameter_constraints
(*e: type [[AST_generic.type_parameter]] *)

(*s: type [[AST_generic.type_parameter_constraints]] *)
  and type_parameter_constraints = type_parameter_constraint list
(*e: type [[AST_generic.type_parameter_constraints]] *)
(*s: type [[AST_generic.type_parameter_constraint]] *)
   and type_parameter_constraint = 
     | Extends of type_
(*e: type [[AST_generic.type_parameter_constraint]] *)
 
(* ------------------------------------------------------------------------- *)
(* Function (or method) definition *)
(* ------------------------------------------------------------------------- *)
(* less: could be merged with variable_definition *)
(*s: type [[AST_generic.function_definition]] *)
and function_definition = {
 fparams: parameters;
 frettype: type_ option; (* return type *)
 (* newscope:
  * note: can be empty statement for methods in interfaces *)
 fbody: stmt;
}
(*e: type [[AST_generic.function_definition]] *)
(*s: type [[AST_generic.parameters]] *)
  and parameters = parameter list
(*e: type [[AST_generic.parameters]] *)
(*s: type [[AST_generic.parameter]] *)
    (* newvar: *)
    and parameter =
     | ParamClassic of parameter_classic
     (*s: [[AST_generic.parameter]] other cases *)
     | ParamPattern of pattern (* in OCaml, but also now JS, and Python2 *)
     (*e: [[AST_generic.parameter]] other cases *)
     (*s: [[AST_generic.parameter]] semgrep extension cases *)
     (* sgrep: ... in parameters
      * note: foo(...x) of Js/Go is using the Variadic attribute, not this *)
     | ParamEllipsis of tok
     (*e: [[AST_generic.parameter]] semgrep extension cases *)
     (*s: [[AST_generic.parameter]] OtherXxx case *)
     | OtherParam of other_parameter_operator * any list
     (*e: [[AST_generic.parameter]] OtherXxx case *)


(*e: type [[AST_generic.parameter]] *)

    (* less: could be merged with variable_definition, or pattern
     * less: could factorize pname/pattrs/pinfo with entity
     *)
(*s: type [[AST_generic.parameter_classic]] *)
    and parameter_classic = { 
     (* alt: use a 'ParamNoIdent of type_' when pname is None instead? *)
     pname:    ident option;
     ptype:    type_ option;
     pdefault: expr  option;
     (*s: [[AST_generic.parameter_classic]] attribute field *)
     (* this covers '...' variadic parameters, see the Variadic attribute *)
     pattrs: attribute list;
     (*e: [[AST_generic.parameter_classic]] attribute field *)
     (*s: [[AST_generic.parameter_classic]] id info field *)
     (* naming *)
     pinfo: id_info; (* Always Param *)
     (*e: [[AST_generic.parameter_classic]] id info field *)
    }
(*e: type [[AST_generic.parameter_classic]] *)
(*s: type [[AST_generic.other_parameter_operator]] *)
  and other_parameter_operator =
     (* Python *)
     | OPO_KwdParam | OPO_SingleStarParam
     (* Go *)
     | OPO_Receiver (* of parameter_classic, used to tag the "self" parameter*)
     (* PHP *) 
     | OPO_Ref (* of parameter_classic *)
(*e: type [[AST_generic.other_parameter_operator]] *)

(* ------------------------------------------------------------------------- *)
(* Variable definition *)
(* ------------------------------------------------------------------------- *)
(* Also used for constant_definition with attrs = [Const].
 * Also used for field definition in a class (and record).
 * less: could use for function_definition with vinit = Some (Lambda (...))
 *  but maybe useful to explicitely makes the difference for now?
 *)
(*s: type [[AST_generic.variable_definition]] *)
and variable_definition = {
  (* todo? should remove vinit and transform a VarDef with init with a VarDef
   * followed by an Assign (possibly to Null). See vardef_to_assign().
   *)
  vinit: expr option;
  vtype: type_ option;
}
(*e: type [[AST_generic.variable_definition]] *)

(* ------------------------------------------------------------------------- *)
(* Type definition *)
(* ------------------------------------------------------------------------- *)
(*s: type [[AST_generic.type_definition]] *)
and type_definition = {
   tbody: type_definition_kind;
  }
(*e: type [[AST_generic.type_definition]] *)

(*s: type [[AST_generic.type_definition_kind]] *)
  and type_definition_kind = 
   | OrType  of or_type_element list  (* enum/ADTs *)           
   (* field.vtype should be defined here 
    * record/struct (for class see class_definition)
    *)
   | AndType of field list bracket

   (* a.k.a typedef in C (and alias type in Go) *)
   | AliasType of type_
   (* Haskell/Hack/Go ('type x foo' vs 'type x = foo' in Go) *)
   | NewType of type_ 

   | Exception of ident (* same name than entity *) * type_ list

   | OtherTypeKind of other_type_kind_operator * any list
(*e: type [[AST_generic.type_definition_kind]] *)

(*s: type [[AST_generic.or_type_element]] *)
    and or_type_element =
      (* OCaml *)
      | OrConstructor of ident * type_ list
      (* C *)
      | OrEnum of ident * expr option
      (* Java? *)
      | OrUnion of ident * type_

      | OtherOr of other_or_type_element_operator * any list
(*e: type [[AST_generic.or_type_element]] *)

(*s: type [[AST_generic.other_or_type_element_operator]] *)
       and other_or_type_element_operator =
       (* Java *)
       | OOTEO_EnumWithMethods | OOTEO_EnumWithArguments
(*e: type [[AST_generic.other_or_type_element_operator]] *)

 (* Field definition and use, for classes and records.
  * note: I don't call it field_definition because it's used both to
  * define the shape of a field (a definition), and when creating
  * an actual field (a value).
  * old: there used to be a FieldVar and FieldMethod similar to
  * VarDef and FuncDef but they are now instead in FieldStmt(DefStmt).
  * this simplifies sgrep too so that a function pattern can match
  * toplevel functions, nested functions, and methods.
  * Note: the FieldStmt(DefStmt(FuncDef(...))) can have empty body
  * for interface methods.
  *)
(*s: type [[AST_generic.field]] *)
  and field = 
    | FieldStmt of stmt
    (*s: [[AST_generic.field]] other cases *)
    | FieldDynamic of expr (* dynamic name *) * attribute list * expr (*value*)
    (* less: could abuse FieldStmt(ExprStmt(IdSpecial(Spread))) for that *)
    | FieldSpread of tok (* ... *) * expr (* usually a Name *)
    (*e: [[AST_generic.field]] other cases *)
(*e: type [[AST_generic.field]] *)

(*s: type [[AST_generic.other_type_kind_operator]] *)
  and other_type_kind_operator = 
     (* OCaml *)
     | OTKO_AbstractType
(*e: type [[AST_generic.other_type_kind_operator]] *)

(* ------------------------------------------------------------------------- *)
(* Class definition *)
(* ------------------------------------------------------------------------- *)
(* less: could be a special kind of type_definition *)
(*s: type [[AST_generic.class_definition]] *)
and class_definition = {
  ckind: class_kind (* wrap TODO *);

  (* usually just one parent, and type_ should be a TyApply *)
  cextends:     type_ list;
  (* class_kind in type_ must be Interface *)
  cimplements:  type_ list;
  (* class_kind in type_ is usually a Trait *)
  cmixins:      type_ list; (* PHP 'uses' *)

  (* newscope: *)
  cbody: field list bracket;
}
(*e: type [[AST_generic.class_definition]] *)
(*s: type [[AST_generic.class_kind]] *)
  and class_kind = 
    | Class
    | Interface
    | Trait
(*e: type [[AST_generic.class_kind]] *)

(* ------------------------------------------------------------------------- *)
(* Module definition  *)
(* ------------------------------------------------------------------------- *)
(*s: type [[AST_generic.module_definition]] *)
and module_definition = {
  mbody: module_definition_kind;
}
(*e: type [[AST_generic.module_definition]] *)

(*s: type [[AST_generic.module_definition_kind]] *)
  and module_definition_kind =
    | ModuleAlias of name
    (* newscope: *)
    | ModuleStruct of dotted_ident option * item list

    | OtherModule of other_module_operator * any list
(*e: type [[AST_generic.module_definition_kind]] *)

(*s: type [[AST_generic.other_module_operator]] *)
  and other_module_operator =
   (* OCaml *)
   | OMO_Functor
(*e: type [[AST_generic.other_module_operator]] *)

(* ------------------------------------------------------------------------- *)
(* Macro definition *)
(* ------------------------------------------------------------------------- *)
(* Used by cpp in C/C++ *)
(*s: type [[AST_generic.macro_definition]] *)
and macro_definition = {
  macroparams: ident list;
  macrobody: any list;
}
(*e: type [[AST_generic.macro_definition]] *)

(*****************************************************************************)
(* Directives (Module import/export, package) *)
(*****************************************************************************)
(*s: type [[AST_generic.directive]] *)
and directive = 
  (* newvar: *)
  | ImportFrom of tok (* 'import'/'from' for Python, 'include' for C *) * 
                  module_name * ident * alias option (* as name alias *)
  (*s: [[AST_generic.directive]] other imports *)
  | ImportAs   of tok * module_name * alias option (* as name *)
  (* bad practice! hard to resolve name locally *)
  | ImportAll  of tok * module_name * tok (* '.' in Go, '*' in Java/Python *)
  (*e: [[AST_generic.directive]] other imports *)
  (*s: [[AST_generic.directive]] package cases *)
  (* packages are different from modules in that multiple files can reuse
   * the same package name; they are agglomarated in the same package
   *)
  | Package of tok * dotted_ident (* a.k.a namespace *)
  (* for languages such as C++/PHP with scoped namespaces
   * alt: Package of tok * dotted_ident * item list bracket, but less 
   * consistent with other directives, so better to use PackageEnd.
   *)
  | PackageEnd of tok
  (*e: [[AST_generic.directive]] package cases *)
  (*s: [[AST_generic.directive]] OtherXxx cases *)
  | OtherDirective of other_directive_operator * any list
  (*e: [[AST_generic.directive]] OtherXxx cases *)
(*e: type [[AST_generic.directive]] *)

(*s: type [[AST_generic.alias]] *)
  and alias = ident (* as name *)
(*e: type [[AST_generic.alias]] *)

(*s: type [[AST_generic.other_directive_operator]] *)
  and other_directive_operator = 
  (* Javascript *)
  | OI_Export 
  | OI_ImportCss | OI_ImportEffect (* less: not used anymore *)
(*e: type [[AST_generic.other_directive_operator]] *)
  (* C/PHP *)
  (* TODO: Pragma/Declare, move OE_UseStrict here for JS? *)


(*****************************************************************************)
(* Toplevel *)
(*****************************************************************************)
(* item (a.k.a toplevel element, toplevel decl) is now equal to stmt.
 * Indeed, many languages allow nested functions, nested class definitions, 
 * and even nested imports, so it is just simpler to merge item with stmt.
 * This simplifies sgrep too.
 * less: merge with field?
 *)
(*s: type [[AST_generic.item]] *)
and item = stmt
(*e: type [[AST_generic.item]] *)

(*s: type [[AST_generic.program]] *)
and program = item list
(*e: type [[AST_generic.program]] *)

(*****************************************************************************)
(* Any *)
(*****************************************************************************)

(* mentioned in many OtherXxx so must be part of the mutually recursive type *)
(*s: type [[AST_generic.any]] *)
and any =
  (*s: [[AST_generic.any]] semgrep cases *)
  | E of expr
  | S of stmt
  | Ss of stmt list
  (*e: [[AST_generic.any]] semgrep cases *)
  | I of ident
  | T of type_
  | P of pattern
  | At of attribute
  | Def of definition
  | Dir of directive
  | Pr of program
  (*s: [[AST_generic.any]] other cases *)
  | N of name
  | En of entity
  | Pa of parameter
  | Ar of argument
  | Dk of definition_kind
  | Di of dotted_ident
  | Fld of field
  | Tk of tok
  (*e: [[AST_generic.any]] other cases *)
(*e: type [[AST_generic.any]] *)
 (* with tarzan *)

(*s: constant [[AST_generic.special_multivardef_pattern]] *)
(* In JS one can do 'var {x,y} = foo();'. We used to transpile that
 * in multiple vars, but in sgrep one may want to match over those patterns.
 * However those multivars do not fit well with the (entity * definition_kind)
 * model we currently use, so for now we need this ugly hack of converting
 * the statement above in 
 * ({name = "!MultiVarDef"}, VarDef {vinit = Assign (Record {...}, foo())}).
 * This is bit ugly, but at some point we may want to remove completely
 * VarDef by transforming them in Assign (see vardef_to_assign() below)
 * so this temporary hack is not too bad.
 *)
let special_multivardef_pattern = "!MultiVarDef!"
(*e: constant [[AST_generic.special_multivardef_pattern]] *)

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
(*s: constant [[AST_generic.str_of_ident]] *)
let str_of_ident = fst
(*e: constant [[AST_generic.str_of_ident]] *)

(*****************************************************************************)
(* Error *)
(*****************************************************************************)

(*s: exception [[AST_generic.Error]] *)
(* this can be used in the xxx_to_generic.ml file to signal limitations,
 * and can be captured in Error_code.exn_to_error to pinpoint the error
 * location.
 *)
exception Error of string * Parse_info.t
(*e: exception [[AST_generic.Error]] *)

(*s: function [[AST_generic.error]] *)
let error tok msg = 
  raise (Error (msg, tok))
(*e: function [[AST_generic.error]] *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*s: constant [[AST_generic.gensym_counter]] *)
(* You can use 0 for globals, even though this will work only on a single
 * file. Any global analysis will need to set a unique ID for globals too. *)
let gensym_counter = ref 0
(* see sid type in resolved_name *)
(*e: constant [[AST_generic.gensym_counter]] *)
(*s: function [[AST_generic.gensym]] *)
(* see sid type in resolved_name *)
let gensym () = 
  incr gensym_counter;
  !gensym_counter
(* before Naming_AST.resolve can do its job *)
(*e: function [[AST_generic.gensym]] *)
(*s: constant [[AST_generic.sid_TODO]] *)
(* before Naming_AST.resolve can do its job *)
let sid_TODO = -1 
(*e: constant [[AST_generic.sid_TODO]] *)

(*s: constant [[AST_generic.empty_name_info]] *)
let empty_name_info = 
  { name_qualifier = None; name_typeargs = None;}
(*e: constant [[AST_generic.empty_name_info]] *)

(*s: constant [[AST_generic.empty_var]] *)
let empty_var = 
  { vinit = None; vtype = None }
(*e: constant [[AST_generic.empty_var]] *)

(*s: function [[AST_generic.empty_id_info]] *)
let empty_id_info () = 
  { id_resolved = ref None; id_type = ref None;
    id_const_literal = ref None;
  }
(*e: function [[AST_generic.empty_id_info]] *)

(*s: function [[AST_generic.basic_id_info]] *)
let basic_id_info resolved = 
  { id_resolved = ref (Some resolved); id_type = ref None; 
    id_const_literal = ref None;
  }
(*e: function [[AST_generic.basic_id_info]] *)

(*
let name_of_id id = 
  (id, empty_name_info), empty_id_info ()
*)

(*s: function [[AST_generic.param_of_id]] *)
let param_of_id id = { 
    pname = Some id;
    pdefault = None; ptype = None; pattrs = []; pinfo = 
      (basic_id_info (Param, sid_TODO));
}
(*e: function [[AST_generic.param_of_id]] *)
(*s: function [[AST_generic.param_of_type]] *)
let param_of_type typ = {
    ptype = Some typ;
    pname = None; pdefault = None; pattrs = []; pinfo = empty_id_info ();
}
(*e: function [[AST_generic.param_of_type]] *)

(*s: function [[AST_generic.basic_entity]] *)
let basic_entity id attrs = {
  name = id;
  attrs = attrs;
  tparams = []; info = empty_id_info ();
}
(*e: function [[AST_generic.basic_entity]] *)

(*s: function [[AST_generic.basic_field]] *)
let basic_field id vopt typeopt =
  let entity = basic_entity id [] in
  FieldStmt(DefStmt(entity, VarDef { vinit = vopt; vtype = typeopt}))
(*e: function [[AST_generic.basic_field]] *)

(*s: function [[AST_generic.attr]] *)
let attr kwd tok =
  KeywordAttr (kwd, tok)
(*e: function [[AST_generic.attr]] *)

(*s: function [[AST_generic.expr_to_arg]] *)
let expr_to_arg e = 
  Arg e
(*e: function [[AST_generic.expr_to_arg]] *)

(*s: function [[AST_generic.expr_to_pattern]] *)
(* In Go a pattern can be a complex expressions. It is just
 * matched for equality with the thing it's matched against, so in that
 * case it should be a pattern like | _ when expr = x.
 * For Python you can actually have a PatDisj of exception classes.
 * coupling: see pattern_to_expr below
 *)
let rec expr_to_pattern e =
  (* TODO: diconstruct e and generate the right pattern (PatLiteral, ...) *)
  match e with
  | Id (id, info) -> PatId (id, info)
  | Tuple xs -> PatTuple (xs |> List.map expr_to_pattern)
  | L l -> PatLiteral l
  | Container(List, (t1, xs, t2)) -> 
      PatList(t1, xs |> List.map expr_to_pattern, t2)
  (* Todo:  PatKeyVal *)
  | _ -> OtherPat (OP_Expr, [E e])
(*e: function [[AST_generic.expr_to_pattern]] *)

(*s: exception [[AST_generic.NotAnExpr]] *)
exception NotAnExpr
(*e: exception [[AST_generic.NotAnExpr]] *)
(*s: function [[AST_generic.pattern_to_expr]] *)
(* sgrep: this is to treat pattern metavars as expr metavars *)
let rec pattern_to_expr p =
  match p with
  | PatId (id, info) -> Id (id, info)
  | PatTuple xs -> Tuple (xs |> List.map pattern_to_expr)
  | PatLiteral l -> L l
  | PatList (t1, xs, t2) -> 
      Container(List, (t1, xs |> List.map pattern_to_expr, t2))
  | OtherPat (OP_Expr, [E e]) -> e
  | PatAs _ | PatVar _ -> raise NotAnExpr
  | _ -> raise NotAnExpr
(*e: function [[AST_generic.pattern_to_expr]] *)

(*s: function [[AST_generic.expr_to_type]] *)
let expr_to_type e =
  (* TODO: diconstruct e and generate the right type (TyBuiltin, ...) *)
  OtherType (OT_Expr, [E e])
(*e: function [[AST_generic.expr_to_type]] *)

(* old: there was a stmt_to_item before *)
(* old: there was a stmt_to_field before *)

(* see also Java_to_generic.entity_to_param *)
(* see also Python_to_generic.expr_to_attribute *)
(* see also Php_generic.list_expr_to_opt *)
(* see also Php_generic.name_of_qualified_ident (also in Java) *)

(*s: function [[AST_generic.opt_to_empty]] *)
(* todo? should remove? should have an explicit EmptyStmt? *)
let opt_to_empty = function
  | None -> Block []
  | Some e -> e
(*e: function [[AST_generic.opt_to_empty]] *)

(*s: function [[AST_generic.opt_to_label_ident]] *)
let opt_to_label_ident = function
  | None -> LNone
  | Some id -> LId id
(*e: function [[AST_generic.opt_to_label_ident]] *)

(*s: function [[AST_generic.stmt1]] *)
let stmt1 xs =
  match xs with
  | [] -> Block []
  | [st] -> st
  | xs -> Block xs
(*e: function [[AST_generic.stmt1]] *)

(*s: function [[AST_generic.is_boolean_operator]] *)
(* used in abstract interpreter and type for PHP where we now reuse
 * 'AST_generic.arithmetic_operator' above *)
let is_boolean_operator = function
 | Plus (* unary too *) | Minus (* unary too *) 
 | Mult | Div | Mod
 | Pow | FloorDiv | MatMult (* Python *)
 | LSL | LSR | ASR (* L = logic, A = Arithmetic, SL = shift left *) 
 | BitOr | BitXor | BitAnd | BitNot | BitClear (* unary *)
  -> false
 | And | Or | Xor | Not
 | Eq     | NotEq     
 | PhysEq | NotPhysEq 
 | Lt | LtE | Gt | GtE 
 | Cmp | Concat
   -> true
(*e: function [[AST_generic.is_boolean_operator]] *)

(*s: function [[AST_generic.vardef_to_assign]] *)
(* used in controlflow_build and semgrep *)
let vardef_to_assign (ent, def) =
  let name = Id (ent.name, ent.info) in
  let v = 
    match def.vinit with
   | Some v -> v
   | None -> L (Null (Parse_info.fake_info "null"))
  in
  Assign (name, Parse_info.fake_info "=", v)
(*e: function [[AST_generic.vardef_to_assign]] *)

(*s: function [[AST_generic.funcdef_to_lambda]] *)
(* used in controlflow_build *)
let funcdef_to_lambda (ent, def) resolved =
  let idinfo = { (empty_id_info()) with id_resolved = ref resolved } in
  let name = Id (ent.name, idinfo) in
  let v = Lambda def in
  Assign (name, Parse_info.fake_info "=", v)
(*e: function [[AST_generic.funcdef_to_lambda]] *)

(*s: function [[AST_generic.has_keyword_attr]] *)
let has_keyword_attr kwd attrs = 
  attrs |> List.exists (function
    | KeywordAttr (kwd2, _) -> kwd =*= kwd2
    | _ -> false
  )
(*e: function [[AST_generic.has_keyword_attr]] *)

(*s: function [[AST_generic.fake]] *)
(* Try avoid using them! if you build new constructs, you should try
 * to derive the tokens in those new constructs from existing constructs.
 *)
let fake s = Parse_info.fake_info s
(*e: function [[AST_generic.fake]] *)
(*s: function [[AST_generic.fake_bracket]] *)
let fake_bracket x = fake "(", x, fake ")"
(*e: function [[AST_generic.fake_bracket]] *)
(*s: function [[AST_generic.unbracket]] *)
let unbracket (_, x, _) = x
(*e: function [[AST_generic.unbracket]] *)
(*e: pfff/h_program-lang/AST_generic.ml *)
