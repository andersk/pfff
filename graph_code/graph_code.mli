
(* the main types *)
type node = string * Database_code.entity_kind
  type nodeinfo = {
    (* the filename embedded inside token_location can be a readable path *)
    pos: Parse_info.token_location;
    props: Database_code.property list;
  }
type edge = Has | Use
(* !! the main type!! really an hypergraph actually *)
type graph


(* error and statistics *)
type error =
 | NodeAlreadyPresent of node
exception Error of error
val string_of_error: error -> string

type statistics = {
  parse_errors: Common.filename list ref;
 (* could be Parse_info.token_location*)
  lookup_fail: (Parse_info.info * node) list ref; 
  method_calls: (Parse_info.info * resolved) list ref;
  field_access: (Parse_info.info * resolved) list ref;
  unresolved_class_access: Parse_info.info list ref;
  unresolved_calls: Parse_info.info list ref;
}
 and resolved = bool
val empty_statistics: unit -> statistics

(* moving around directories to have less backward dependencies *)
type adjust = (string * string)
(* skip certain edges that are marked as ok regarding backward dependencies *)
type dependency = (node * node)
type whitelist = dependency list



(* IO *)
val load: Common.filename -> graph
val save: graph -> Common.filename -> unit
val default_graphcode_filename: string


val root: node
 val pb: node
  val not_found: node
  val dupe: node
(* val stdlib: node *)

val create_initial_hierarchy: graph -> unit

(* similar API to graph.ml *)

(* graph construction *)
val create: unit -> graph
(* may raise NodeAlreadyPresent *)
val add_node: node -> graph -> unit
val add_nodeinfo: node -> nodeinfo -> graph -> unit
val add_edge: (node * node) -> edge -> graph -> unit
val create_intermediate_directories_if_not_present: 
  graph -> Common.dirname -> unit
val remove_edge: (node * node) -> edge -> graph -> unit

(* graph access *)
val has_node: node -> graph -> bool
val succ: node -> edge -> graph -> node list
(* this is slow, take care, or use mk_eff_use_pred below *)
val pred: node -> edge -> graph -> node list
val mk_eff_use_pred: graph -> (node -> node list)
(* can raise a Not_found exception *)
val parent: node -> graph -> node
val parents: node -> graph -> node list
val children: node -> graph -> node list
val all_children: node -> graph -> node list
(* may raise Not_found *)
val nodeinfo: node -> graph -> nodeinfo
(* should be in readable path if you want your codegraph to be "portable" *)
val file_of_node: node -> graph -> Common.filename
val privacy_of_node: node -> graph -> Database_code.privacy
val shortname_of_node: node -> string

(* iteration *)
val iter_use_edges: (node -> node -> unit) -> graph -> unit
val iter_nodes: (node -> unit) -> graph -> unit
val all_use_edges: graph -> (node * node) list
val all_nodes: graph -> node list

(* statistics *)
val nb_nodes: graph -> int
val nb_use_edges: graph -> int
val print_statistics: statistics -> graph -> unit

(* algorithms *)
val group_edges_by_files_edges:
  (node * node) list -> graph ->
  ((Common.filename * Common.filename) * (node * node) list) list
val strongly_connected_components_use_graph:
  graph -> (node list array * (node, int) Hashtbl.t)
(* bottom nodes have 0 for their numbering *)
val bottom_up_numbering:
  graph -> (node, int) Hashtbl.t
(* top nodes have 0 for their numbering, less useful in practice *)
val top_down_numbering:
  graph -> (node, int) Hashtbl.t

(* example builder *)
val graph_of_dotfile: Common.filename -> graph


(* debugging support *)
val string_of_node: node -> string
val display_with_gv: graph -> unit

(* adjustments *)
val load_adjust: Common.filename -> adjust list
val load_whitelist: Common.filename -> whitelist
val save_whitelist: whitelist -> Common.filename -> graph -> unit
(* does side effect on the graph *)
val adjust_graph: graph -> adjust list -> whitelist -> unit
