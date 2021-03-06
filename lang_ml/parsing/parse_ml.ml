(* Yoann Padioleau
 * 
 * Copyright (C) 2010 Facebook
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License (GPL)
 * version 2 as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * file license.txt for more details.
 *)
open Common 

module Flag = Flag_parsing
module TH   = Token_helpers_ml
module PI = Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type program_and_tokens = 
  Cst_ml.program option * Parser_ml.token list

(*****************************************************************************)
(* Error diagnostic  *)
(*****************************************************************************)
let error_msg_tok tok = 
  Parse_info.error_message_info (TH.info_of_tok tok)

(*****************************************************************************)
(* Lexing only *)
(*****************************************************************************)

let tokens2 file = 
  let token = Lexer_ml.token in
  Parse_info.tokenize_all_and_adjust_pos 
    file token TH.visitor_info_of_tok TH.is_eof
          
let tokens a = 
  Common.profile_code "Parse_ml.tokens" (fun () -> tokens2 a)

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)
let parse2 filename = 

  let stat = Parse_info.default_stat filename in
  let toks = tokens filename in

  let tr, lexer, lexbuf_fake = 
    Parse_info.mk_lexer_for_yacc toks TH.is_comment in

  try 
    (* -------------------------------------------------- *)
    (* Call parser *)
    (* -------------------------------------------------- *)
    let xs =
      Common.profile_code "Parser_ml.main" (fun () ->
        if filename =~ ".*\\.mli"
        then Parser_ml.interface      lexer lexbuf_fake
        else Parser_ml.implementation lexer lexbuf_fake
      )
    in
    stat.PI.correct <- (Common.cat filename |> List.length);
    (Some xs, toks), stat
      
  with Parsing.Parse_error   ->

    let cur = tr.PI.current in
    if not !Flag.error_recovery
    then raise (PI.Parsing_error (TH.info_of_tok cur));

    if !Flag.show_parsing_error
    then begin
      pr2 ("parse error \n = " ^ error_msg_tok cur);
      let filelines = Common2.cat_array filename in
      let checkpoint2 = Common.cat filename |> List.length in
      let line_error = TH.line_of_tok cur in
      Parse_info.print_bad line_error (0, checkpoint2) filelines;
    end;

    stat.PI.bad     <- Common.cat filename |> List.length;
    (None, toks), stat

let parse a = 
  Common.profile_code "Parse_ml.parse" (fun () -> parse2 a)

let parse_program file = 
  let ((astopt, _toks), _stat) = parse file in
  Common2.some astopt
