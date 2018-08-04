(*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

open Util
open ErgoComp

(** Ergo errors *)
exception Ergo_Error of eerror
let mk_position_point_of_loc pos =
  { offset = pos.Lexing.pos_cnum;
    line = pos.Lexing.pos_lnum;
    column = pos.Lexing.pos_cnum - pos.Lexing.pos_bol; }
let mk_position_of_loc_pair filename start_pos end_pos =
  { loc_file = Util.char_list_of_string filename;
    loc_start = mk_position_point_of_loc start_pos;
    loc_end = mk_position_point_of_loc end_pos; }
let mk_provenance_of_loc_pair filename start_pos end_pos =
  ErgoCompiler.prov_loc (mk_position_of_loc_pair filename start_pos end_pos)
let ergo_system_error msg =
  ESystemError (dummy_provenance,char_list_of_string msg)
let ergo_parse_error msg filename start_pos end_pos =
  EParseError (mk_provenance_of_loc_pair filename start_pos end_pos, char_list_of_string msg)
let ergo_compilation_error msg filename start_pos end_pos =
  ECompilationError (mk_provenance_of_loc_pair filename start_pos end_pos, char_list_of_string msg)
let ergo_type_error msg filename start_pos end_pos =
  ETypeError (mk_provenance_of_loc_pair filename start_pos end_pos, char_list_of_string msg)
let ergo_runtime_error msg filename start_pos end_pos =
  ERuntimeError (mk_provenance_of_loc_pair filename start_pos end_pos, char_list_of_string msg)

let ergo_raise error =
  raise (Ergo_Error error)

let error_kind error =
  begin match error with
  | ESystemError (_,_) -> "SystemError"
  | EParseError (_,_) -> "ParseError"
  | ECompilationError (_,_) -> "CompilationError"
  | ETypeError (_,_) -> "TypeError"
  | ERuntimeError (_,_) -> "RuntimeError"
  end

let error_message error =
  let msg = 
    begin match error with
    | ESystemError (_,msg) -> msg
    | EParseError (_,msg) -> msg
    | ECompilationError (_,msg) -> msg
    | ETypeError (_,msg) -> msg
    | ERuntimeError (_,msg) -> msg
    end
  in string_of_char_list msg

let error_loc_start error =
  begin match error with
  | ESystemError (loc,_) -> (loc_of_provenance loc).loc_start
  | EParseError (prov,_) -> (loc_of_provenance prov).loc_start
  | ECompilationError (prov,_) -> (loc_of_provenance prov).loc_start
  | ETypeError (prov,_) -> (loc_of_provenance prov).loc_start
  | ERuntimeError (prov,_) -> (loc_of_provenance prov).loc_start
  end
let error_loc_end error =
  begin match error with
  | ESystemError (prov,_) -> (loc_of_provenance prov).loc_end
  | EParseError (prov,_) -> (loc_of_provenance prov).loc_end
  | ECompilationError (prov,_) -> (loc_of_provenance prov).loc_end
  | ETypeError (prov,_) -> (loc_of_provenance prov).loc_end
  | ERuntimeError (prov,_) -> (loc_of_provenance prov).loc_end
  end

let underline_prov source prov =
  begin try
    let loc = loc_of_provenance prov in
    let lines = String.split_on_char '\n' source in
    let line = List.nth lines (loc.loc_start.line - 1) in
    let underline =
      String.init
        (String.length line)
        (fun n ->
           if (n >= loc.loc_start.column && n < loc.loc_end.column)
           then '^'
           else ' ')
    in
    "\n" ^ line ^ "\n" ^ underline
  with
  | _ -> ""
  end

let no_file file =
  file = "" || file = "stdin"

let string_of_error_prov prov =
  let loc = loc_of_provenance prov in
  let file = Util.string_of_char_list loc.loc_file in
  (if no_file file then "" else "file " ^ file ^ " ")
  ^ "line " ^ (string_of_int loc.loc_start.line)
  ^ " col " ^ (string_of_int loc.loc_start.column)

let get_source source_table file =
  begin try Some (List.assoc file source_table) with
  | _ -> None
  end

let file_of_prov prov =
  Util.string_of_char_list (loc_of_provenance prov).loc_file
let underline_source source_table prov =
  let file = file_of_prov prov in
  let source = get_source source_table file in
  begin match source with
  | None -> ""
  | Some source -> underline_prov source prov
  end

let string_of_error f x error =
  begin match error with
  | ESystemError _ ->
      "[SystemError] " ^ (error_message error)
  | EParseError (prov, _) ->
      "[ParseError at " ^ (string_of_error_prov prov) ^ "] " (* ^ (error_message error) *) ^ (f x prov)
  | ECompilationError (prov, _) ->
      "[CompilationError at " ^ (string_of_error_prov prov) ^ "] " ^  (error_message error) ^ (f x prov)
  | ETypeError (prov, _) ->
      "[TypeError at " ^ (string_of_error_prov prov) ^ "] " ^ (error_message error) ^ (f x prov)
  | ERuntimeError (prov, _) ->
      "[RuntimeError at " ^ (string_of_error_prov prov) ^ "] " ^  (error_message error) ^ (f x prov)
  end
let string_of_error_with_source source error =
  string_of_error underline_prov source error
let string_of_error_with_table source_table error =
  string_of_error underline_source source_table error

(** Version number *)
let ergo_version = string_of_char_list ergo_version

let get_version cmd () =
  print_endline (cmd ^ ", version " ^ ergo_version);
  exit 0

(** Additional utility functions *)
let process_file f (file_name, file_content) =
  f (file_name,file_content)

type result_file = {
  res_file : string;
  res_content : string;
}

let make_result_file ext source_file s =
  let fpref = Filename.chop_extension source_file in
  let fout = outname (target_f None fpref) ext in
  { res_file = fout;
    res_content = s; }

let wrap_jerrors f e =
  begin match e with
  | Failure e -> ergo_raise e
  | Success x -> f x
  end

(** Ergo call *)
let ergo_call contract_name =
  Util.string_of_char_list
    (ErgoCompiler.javascript_identifier_sanitizer (Util.char_list_of_string contract_name))

(** CTO import *)
let cto_import_decl_of_import_namespace ns =
  begin match String.rindex_opt ns '.' with
  | None ->
      ergo_raise (ergo_system_error ("Malformed import: '" ^ ns ^ "' (should have at least one '.')"))
  | Some i ->
      let namespace = char_list_of_string (String.sub ns 0 i) in
      let criteria_str = String.sub ns (i+1) (String.length ns - (i+1)) in
      begin match criteria_str with
      | "*" -> ImportAll (dummy_provenance, namespace)
      | _ -> ImportName (dummy_provenance,namespace,char_list_of_string criteria_str)
      end
  end

(** Command line args *)
let patch_extension f ext1 ext2 =
  begin try
    let extension = Filename.extension f in
    if extension = ext1
    then
      (Filename.chop_suffix f ext1) ^ ext2
    else f
  with
  | _ -> f
  end

let patch_cto_extension f =
  patch_extension f ".cto" ".ctoj"
let unpatch_cto_extension f =
  patch_extension f ".ctoj" ".cto"

let patch_argv argv =
  Array.map patch_cto_extension argv

let anon_args cto_files input_files f =
  let extension = Filename.extension f in
  if extension = ".ctoj"
  then cto_files := (f, Util.string_of_file f) :: !cto_files
  else if extension = ".ergo"
  then input_files := (f, Util.string_of_file f) :: !input_files
  else ergo_raise (ergo_system_error (f ^ " is not cto, ctoj or ergo file"))

let parse_args args_list usage args gconf =
  let parse args l f msg =
    try
      Arg.parse_argv args l f msg
    with
    | Arg.Bad msg -> Printf.eprintf "%s" msg; exit 2
    | Arg.Help msg -> Printf.printf "%s" msg; exit 0
  in
  let input_files = ref [] in
  let cto_files = ref [] in
  parse args (args_list gconf) (anon_args cto_files input_files) usage;
  (List.rev !cto_files, List.rev !input_files)

type label =
  | ErgoLabel of string
  | CTOLabel of string

let label_name_of_ergo_input m =
  Util.string_of_char_list m.module_namespace
let label_name_of_cto_input c =
  Util.string_of_char_list c.cto_package_namespace
let label_of_input input : label =
  begin match input with
  | InputErgo m -> ErgoLabel (label_name_of_ergo_input m)
  | InputCTO c -> CTOLabel (label_name_of_cto_input c)
  end

let file_of_input input : string =
  begin match input with
  | InputErgo m -> Util.string_of_char_list m.module_file
  | InputCTO c -> Util.string_of_char_list c.cto_package_file
  end

let import_cto_name im =
  begin match im with
  | ImportAll (_, ns)
  | ImportName (_, ns, _) -> [CTOLabel (Util.string_of_char_list ns)]
  | _ -> []
  end

let import_ergo_name im =
  begin match im with
  | ImportAll (_, ns)
  | ImportName (_, ns, _) -> [CTOLabel (Util.string_of_char_list ns);ErgoLabel (Util.string_of_char_list ns);]
  | _ -> []
  end

let module_import_name decl =
  begin match decl with
  | DImport (_, im) -> import_ergo_name im
  | _ -> []
  end

let module_imports label_name decls =
  if label_name = "org.accordproject.ergo.stdlib"
  then
    (CTOLabel "org.hyperledger.composer.system")
    :: List.concat (List.map module_import_name decls)
  else
    (CTOLabel "org.hyperledger.composer.system")
    :: (CTOLabel label_name)
    :: (ErgoLabel "org.accordproject.ergo.stdlib")
    :: List.concat (List.map module_import_name decls)

let cto_imports label_name decls =
  if label_name = "org.hyperledger.composer.system"
  then
    List.concat (List.map import_cto_name decls)
  else
    (CTOLabel "org.hyperledger.composer.system")
    :: List.concat (List.map import_cto_name decls)

let lookup_inputs_from_label all_inputs label =
  begin try
    [List.assoc label (List.map (fun x -> (label_of_input x, x)) all_inputs)]
  with
  | _ -> []
  end

let edges_of_input all_inputs input =
  begin match input with
  | InputErgo m ->
      List.concat
        (List.map (lookup_inputs_from_label all_inputs)
           (module_imports (label_name_of_ergo_input m) m.module_declarations))
  | InputCTO c ->
      List.concat
        (List.map (lookup_inputs_from_label all_inputs)
           (cto_imports (label_name_of_cto_input c) c.cto_package_imports))
  end

let graph_of_inputs all_inputs =
  List.map (fun x -> (x, edges_of_input all_inputs x)) all_inputs

let labels_of_graph all_inputs =
  let graph = graph_of_inputs all_inputs in
  List.map
    (fun xy ->
       (file_of_input (fst xy),
        List.map file_of_input (snd xy)))
    graph

let cycle_of_path path =
  String.concat " -> " path

let topo_sort_inputs all_inputs =
  begin try
    Util.toposort label_of_input file_of_input (graph_of_inputs all_inputs)
  with
  | TopoCycle path ->
      ergo_raise (ergo_system_error ("Circular imports: " ^ cycle_of_path path))
  end

let rec get_last_ergo l =
  begin match l with
  | [] -> ([], None)
  | (InputCTO x) :: rest ->
      let (rest', last) = get_last_ergo rest in
      (InputCTO x :: rest', last)
  | (InputErgo x) :: rest ->
      let (rest', last) = get_last_ergo rest in
      begin match last with
      | None -> (rest', Some x)
      | Some x' -> (InputErgo x :: rest', Some x')
      end
  end

