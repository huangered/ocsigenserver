(* Ocsigen
 * Copyright (C) 2005 Vincent Balat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)


(** Ocsigen.ml defines the functions you need to interact with Ocsigen:
   - To create the "typed services" and associate them to a path (directories/name)
   - To specify the types and names of the parameters of this service
   - To register the functions that generate pages for each of these services
   - To create links or forms etc.
 *)

open XHTML.M
open Xhtmltypes

(** {2 Types} *)

type page = xhtml elt
(** Type of web pages. It is the result type for function generating xhtml *)

type service_kind = [`Internal_Service of [`Public_Service | `Local_Service] | `External_Service]
(** Kind of service *)

type ('get,'post,'kind,'tipo,'getnames,'postnames) service
(** Typed services. The ['kind] parameter is subset of service_kind. ['get] 
and ['post] are the type of GET and POST parameters. *)

type url_path = string list
(** This type is used to represent URL paths; For example the path [coucou/ciao] is represented by the list [\["coucou";"ciao"\]] *)

type current_url
(** This type is used to represent the current URL paths. It is used to create relative links from the current page. *)

val string_list_of_current_url : current_url -> url_path
(** Converts a [current_url] to an [url_path] *)

val reconstruct_url_path : url_path -> string
(** Reconstructs the string from a [url_path] *)

val remove_slash : url_path -> url_path
(** remove the first [/] in a path *)

(** {2 Types of pages parameters} *)

(** Here are some examples of how to specify the types and names of pages parameters:
 - [unit] for a page without parameter.
 - [(int "myvalue")] for a page that takes one parameter, of type [int], called [myvalue]. (You must register a function of type [int ->] {{:#TYPEpage}[page]}).
 - [(int "myvalue" ** string "mystring")] for a page that takes two parameters, one of type [int] called [myvalue], and one of type [string] called [mystring]. (The function you will register has a parameter of type [(int * string)]).
 - [list "l" (int "myvalue" ** string "mystring")] for a page that takes a list of pairs. (The function you will register has a parameter of type [(int * string) list]).

 *)

type server_params = {full_url: string;
		      current_url: current_url;
		      user_agent: string;
		      ip: Unix.inet_addr;
		      get_params: (string * string) list;
		      post_params: (string * string) list}
(** Type of server parameters *)

type ('a, 'b) binsum = Inj1 of 'a | Inj2 of 'b
(** Binary sums *)

type 'a name = string
(** Type for names of page parameters *)

type ('a, 'b, 'c) params_type
(** Type for parameters of a web page *)

type 'an listnames =
    {it:'el 'a. ('an -> 'el -> 'a list) -> 'el list -> 'a list -> 'a list}
(** Type of the iterator used to construct forms from lists *)

val int : string -> (int, [ `WithoutSuffix ], int name) params_type
(** [int s] tells that the page take an integer as parameter, labeled [s] *)

val string :
  string -> (string, [ `WithoutSuffix ], string name) params_type
(** [string s] tells that the page take a string as parameter, labeled [s] *)

val bool :
  string -> (bool, [ `WithoutSuffix ], bool name) params_type
(** [bool s] tells that the page take a boolean as parameter, labeled [s]
    (to use for example with checkboxes) *)

val unit : (unit, [ `WithoutSuffix ], unit name) params_type
(** used for pages that don't have any parameters *)

val user_type :
  (string -> 'a) ->
  ('a -> string) -> string -> ('a, [ `WithoutSuffix ], 'a name) params_type
(** Allows to use whatever type you want for a parameter of the page.
   [user_type s_to_t t_to_s s] tells that the page take a parameter, labeled [s], and that the server will have to use [s_to_t] and [t_to_s] to make the conversion from and to string.
 *)

val sum :
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  (('a, 'a) binsum, [ `WithoutSuffix ], 'b * 'b) params_type
val prod :
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  ('c, [ `WithoutSuffix ], 'd) params_type ->
  ('a * 'c, [ `WithoutSuffix ], 'b * 'd) params_type
(** See [**] above *)

val option :
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  ('a option, [ `WithoutSuffix ], 'b) params_type
(** Use this if you want a parameter to be optional *)

val list :
  string ->
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  ('a list, [ `WithoutSuffix ], 'b listnames) params_type
(** The page takes a list of parameters. 
   The first parameter of this function is the name of the list. *)

val ( ** ) :
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  ('c, [ `WithoutSuffix ], 'd) params_type ->
  ('a * 'c, [ `WithoutSuffix ], 'b * 'd) params_type
(** This is a combinator to allow the page to take several parameters (see examples above) Warning: it is a binary operator. Pages cannot take tuples but only pairs. *)

val suffix_only : (string, [ `WithSuffix ], string name) params_type
(** Tells that the only parameter of the function that will generate the page is the suffix of the URL of the current page. (see {{:#VALregister_new_service}[register_new_service]}) *)

val suffix :
  ('a, [ `WithoutSuffix ], 'b) params_type ->
  (string * 'a, [ `WithSuffix ], string name * 'b) params_type
(** Tells that the function that will generate the page takes a pair whose first element is the suffix of the URL of the current page. (see {{:#VALregister_new_service}[register_new_service]}). e.g. [suffix (int "i" ** string "s")] *)


(** {2 Pages registration} *)

val new_service :
  url:url_path ->
  ?prefix:bool ->
  get_params:('a, [< `WithSuffix | `WithoutSuffix ] as 'b, 'c) params_type ->
  unit ->
  ('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, unit name) service
(** [new_service ~url:p ~get_params:pa ()] creates an {{:#TYPEservice}[service]} associated to the {{:#TYPEurl_path}[url_path]} [p] and that takes the parameters [pa]. 

If you specify [~prefix:true], your service will match all requests from client beginning by [path]. You can have access to the suffix of the URL using {{:VALsuffix}[suffix]} or {{:VALsuffix_only}[suffix_only]}. For example [new_service ["mysite";"mywiki"] ~prefix:true suffix_only] will match all the URL of the shape [http://myserver/mysite/mywiki/thesuffix]*)

val new_external_service :
  url:url_path ->
  ?prefix:bool ->
  get_params:('a, [< `WithSuffix | `WithoutSuffix ] as 'b, 'c) params_type ->
  post_params:('d, [ `WithoutSuffix ], 'e) params_type ->
  unit -> ('a, 'd, [ `External_Service ], 'b, 'c, 'e) service
(** Creates an service for an external web site *)

val new_auxiliary_service :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, 'd) service ->
  ('a, unit, [ `Internal_Service of [ `Local_Service ] ], 'b, 'c, 'd) service
(** Creates another version of an already existing service, where you can register another treatment. The two versions are automatically distinguished thanks to an extra parameter. It allows to have several links towards the same page, that will behave differently. See the tutorial for more informations.*)

val register_service :
  service:('a, 'b, [ `Internal_Service of 'c ], [< `WithSuffix | `WithoutSuffix ],
       'd, 'e)
      service ->
  (server_params -> 'a -> 'b -> page) -> unit
(** Register an service in the global table of the server 
   with the associated generation function.
   [register_service service t f] will associate the service [service] to the function [f].
   [f] is the function that creates a page. 
   It takes three parameters. The first one has type [server_params]
   and allows to have acces to informations about the request.
   The second and third ones are respectively GET and POST parameters.
   For example if [t] is (int "s"), then ['a] is int.
 *)

val register_service_for_session :
  service:('a, 'b, [ `Internal_Service of 'c ], [< `WithSuffix | `WithoutSuffix ],
       'd, 'e)
      service ->
  (server_params -> 'a -> 'b -> page) -> unit
(** Registers an service and the associated function in the session table.
   If the same client does a request to this service, this function will be
   used instead of the one from the global table.

   Warning:
   - All service must be registered in the global table during initialisation,
   but never after,
   - You (obviously) can't register an service in a session table 
   when no session is active
 *)


val register_new_service :
  url:url_path ->
  ?prefix:bool ->
  get_params:('a, [< `WithSuffix | `WithoutSuffix ] as 'b, 'c) params_type ->
  (server_params -> 'a -> unit -> page) ->
  ('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, unit name) service
(** Same as [new_service] followed by [register_service] *)

val register_new_auxiliary_service :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'b, 'c, 'd)
           service ->
  (server_params -> 'a -> unit -> page) ->
  ('a, unit, [ `Internal_Service of [ `Local_Service ] ], 'b, 'c, 'd) service
(** Same as [new_auxiliary_service] followed by [register_service] *)

val register_new_auxiliary_service_for_session :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'b, 'c, 'd)
           service ->
  (server_params -> 'a -> unit -> page) ->
  ('a, unit, [ `Internal_Service of [ `Local_Service ] ], 'b, 'c, 'd) service
(** Same as [new_auxiliary_service] followed by [register_service_for_session] *)

val new_post_service :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c,
            unit name)
           service ->
  post_params:('d, [ `WithoutSuffix ], 'e) params_type ->
  ('a, 'd, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, 'e) service
(** Creates an service that takes POST parameters. 
   [fallback] is the same service without POST parameters.
   You can create an service with POST parameters if the same service does not exist
   without POST parameters. Thus, the user can't bookmark a page that does not
   exist.
 *)

val new_post_auxiliary_service :
  fallback:('a, 'b, [ `Internal_Service of [ `Public_Service ] ], 'c, 'd, 'e) service ->
  post_params:('f, [ `WithoutSuffix ], 'g) params_type ->
  ('a, 'f, [ `Internal_Service of [ `Local_Service ] ], 'c, 'd, 'g) service
(** Creates a auxiliary service with POST parameters *)

val register_new_post_service :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'b, 'c, unit name)
           service ->
  post_params:('d, [ `WithoutSuffix ], 'e) params_type ->
  (server_params -> 'a -> 'd -> page) ->
  ('a, 'd, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, 'e) service
(** Same as [new_post_service] followed by [register_post_service] *)

val register_new_post_auxiliary_service :
  fallback:('a, 'b, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'c, 'd, 'e)
           service ->
  post_params:('f, [ `WithoutSuffix ], 'g) params_type ->
  (server_params -> 'a -> 'f -> page) ->
  ('a, 'f, [ `Internal_Service of [ `Local_Service ] ], 'c, 'd, 'g) service
(** Same as [new_post_auxiliary_service] followed by [register_post_service] *)

val register_new_post_auxiliary_service_for_session :
  fallback:('a, 'b, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'c, 'd, 'e)
           service ->
  post_params:('f, [ `WithoutSuffix ], 'g) params_type ->
  (server_params -> 'a -> 'f -> page) ->
  ('a, 'f, [ `Internal_Service of [ `Local_Service ] ], 'c, 'd, 'g) service
(** Same as [new_post_auxiliary_service] followed by [register_post_service_for_session] *)

val static_dir :
  (string, unit, [ `Internal_Service of [ `Public_Service ] ], [ `WithSuffix ],
   string name, unit name)
  service
(** The service that correponds to the directory where static pages are.
   This directory is chosen in the config file (ocsigen.conf).
   This service takes the name of the static file as a parameter.
 *)

val close_session : unit -> unit
(** Close the session *)


(** {2 Registering actions} *)

(* actions (new 10/05) *)
type ('a,'b) action
(** Type of actions. Actions are like services but they do not generate any page.
   When an action is called, the function associated is launched and
   current page is (possibly) reloaded.
 *)

val new_action :
  post_params:('a, [ `WithoutSuffix ], 'b) params_type -> ('a, 'b) action
(** Creates an action *)

val register_action :
  action:('a, 'b) action ->
  (server_params -> 'a -> unit) -> unit
(** Register an action in the global table *)

val register_action_for_session :
  action:('a, 'b) action ->
  (server_params -> 'a -> unit) -> unit
(** Register an action in the session table *)

val register_new_action :
  post_params:('a, [ `WithoutSuffix ], 'b) params_type ->
  (server_params -> 'a -> unit) -> ('a, 'b) action
(** Same as [new_action] followed by [register_action] *)

val register_new_action_for_session :
  params:('a, [ `WithoutSuffix ], 'b) params_type ->
  (server_params -> 'a -> unit) -> ('a, 'b) action
(** Same as [new_action] followed by [register_action_for_session] *)


(** {2 Creating links, forms, etc.} *)

val a : ?a:([< a_attrib > `Href ] attrib list) ->
  ('get, unit, 'b, [< `WithSuffix | `WithoutSuffix ], 'c, unit name) service ->
    current_url -> 
      a_content elt list -> 'get -> [>a] XHTML.M.elt
(** [a service current cont ()] creates a link from [current] to [service]. The text of
   the link is [cont]. For example [cont] may be something like
   [\[pcdata "click here"\]]. To know the current URL (for [current]),
   use {{:#VALcurrent_url}current_url}.

   The last  parameter is for GET parameters.
   For example [a service current cont (42,"hello")]

 The [~a] optional parameter is used for extra attributes 
   (see the module XHTML.M) *)

val css_link : ?a:([< link_attrib > `Href `Rel `Type ] attrib list) ->
  uri -> [> link ] elt
(** Creates a [<link>] tag for a Cascading StyleSheet (CSS). *)

val js_script : ?a:([< script_attrib > `Src ] attrib list) ->
  uri -> [> script ] elt
(** Creates a [<script>] tag to add a javascript file *)

val make_uri :
  ('a, unit, 'b, [< `WithSuffix | `WithoutSuffix ], 'c, 'd) service ->
  current_url -> 'a -> uri
(** Create the text of the service. Like the [a] function, it may take
   extra parameters. *)


val get_form : ?a:([< form_attrib > `Method ] attrib list) ->
  ('get, unit, 'c, 'd, 'getnames, unit name) service ->
  current_url -> ('getnames -> form_content elt list) -> [>form] elt
(** [get_form service current formgen] creates a GET form from [current] to [service]. 
   The content of
   the form is generated by the function [formgen], that takes the names
   of page parameters as parameters. *)

val post_form : ?a:([< form_attrib > `Method ] attrib list) ->
  ('get, 'post, 'c, [< `WithSuffix | `WithoutSuffix ], 'getnames, 'postnames) service ->
  current_url ->
  ('postnames -> form_content elt list) -> 'get -> [>form] elt
(** [post_form service current formgen] creates a POST form from [current] 
   to [service]. The last parameter is for GET parameters (as in the function [a]).
*)

(*
val img : ?a:([< img_attrib ] attrib list) ->
  alt:string ->
  ('a, form_content elt list, 'ca,'cform, 'curi, 'd, 'e, 'f, 'g) service -> current_url -> 'cimg
*)

val int_input : ?a:([< input_attrib > `Input_Type `Name ] attrib list ) -> 
  int name -> [> input ] elt
(** Creates an [<input>] tag for an integer *)

val hidden_int_input : 
    ?a:([< input_attrib > `Input_Type `Name `Value ] attrib list ) -> 
      int name -> int -> [> input ] elt
(** Creates an hidden [<input>] tag for an integer *)

val string_input : 
    ?a:([< input_attrib > `Input_Type `Name ] attrib list ) -> string name -> 
      [> input ] elt
(** Creates an [<input>] tag for a string *)

val password_input : 
    ?a:([< input_attrib > `Input_Type `Name ] attrib list ) -> string name -> 
      [> input ] elt
(** Creates an [<password>] tag *)

val checkbox_input :
    ?a:([< input_attrib > `Input_Type `Name ] attrib list ) -> 
  bool name -> [> input ] elt
(** Creates a checkbox [<input>] tag *)

val radio_input : ?a:([< input_attrib > `Input_Type `Name ] attrib list ) -> 
  string name -> [> input ] elt
(** Creates a radio [<input>] tag *)

val textarea : ?a:([< textarea_attrib > `Name ] attrib list ) -> 
  string name -> rows:number -> cols:number -> [ `PCDATA ] XHTML.M.elt ->
    [> textarea ] elt
(** Creates a [<textarea>] tag *)

val submit_input : ?a:([< input_attrib > `Input_Type `Value ] attrib list ) -> 
  string -> [> input ] elt
(** Creates a submit [<input>] tag *)


val action_a : ?a:([< a_attrib > `Href ] attrib list) ->
  ?reload:bool ->
    ('a,'b) action -> 
      server_params -> 
	a_content elt list -> 
	  [> form] elt
(** Creates a link that will perform an action (see {{:#TYPEaction}[action]}).
   If [~reload:false] is specified, the current page will not be reloaded.
 *)

val action_form : ?a:([< form_attrib > `Method ] attrib list) ->
    ?reload:bool ->
      ('a, 'b) action ->
	server_params -> 
	  ('b -> form_content elt list) ->
	    [> form] elt
(** Creates a form that will perform an action (see {{:#TYPEaction}[action]}).
   If [~reload:false] is specified, the current page will not be reloaded.
 *)

(**/**) (* Internal functions *)

(** return a page from an service and parameters *)
val get_page :
  url_path * string * string * int option * (string * string) list *
  (string * string) list * string -> 
  Unix.sockaddr -> string option -> string option * page * string

val make_action :
  string -> (string * string) list ->
  url_path * string * string * int option * (string * string) list *
  (string * string) list * string -> 
  Unix.sockaddr -> string option -> string option * unit * string


val state_param_name : string
val action_prefix : string
val action_name : string
val action_reload : string

(** Profiling *)
val number_of_sessions : unit -> int
val get_number_of_connected : unit -> int

val get_number_of_connected : unit -> int
(** Server internal functions: *)
(** loads a module in the server *)
val load_ocsigen_module : dir:url_path -> cmo:string -> unit
val incr_connected : unit -> unit
val decr_connected : unit -> unit


exception Ocsigen_service_created_outside_site_loading
exception Ocsigen_duplicate_registering of string
exception Ocsigen_page_erasing of string
exception Ocsigen_there_are_unregistered_services of string
exception Ocsigen_register_for_session_outside_session
exception Ocsigen_error_while_loading of string
exception Ocsigen_Is_a_directory
exception Ocsigen_404
val end_initialisation : unit -> unit
















(* DEPRECATED FUNCTIONS :

val new_url :
  path:url_path ->
  ?prefix:bool ->
  get_params:('a, [< `WithSuffix | `WithoutSuffix ] as 'b, 'c) params_type ->
  unit ->
  ('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, unit name) service

val new_external_url :
  path:url_path ->
  ?prefix:bool ->
  get_params:('a, [< `WithSuffix | `WithoutSuffix ] as 'b, 'c) params_type ->
  post_params:('d, [ `WithoutSuffix ], 'e) params_type ->
  unit -> ('a, 'd, [ `External_Service ], 'b, 'c, 'e) service

val new_state_url :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, 'd) service ->
  ('a, unit, [ `Internal_Service of [ `Local_Service ] ], 'b, 'c, 'd) service

val register_url :
  url:('a, 'b, [ `Internal_Service of 'c ], [< `WithSuffix | `WithoutSuffix ],
       'd, 'e)
      service ->
  (server_params -> 'a -> 'b -> page) -> unit

val register_url_for_session :
  url:('a, 'b, [ `Internal_Service of 'c ], [< `WithSuffix | `WithoutSuffix ],
       'd, 'e)
      service ->
  (server_params -> 'a -> 'b -> page) -> unit

val register_new_url :
  path:url_path ->
  ?prefix:bool ->
  get_params:('a, [< `WithSuffix | `WithoutSuffix ] as 'b, 'c) params_type ->
  (server_params -> 'a -> unit -> page) ->
  ('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, unit name) service

val register_new_state_url :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'b, 'c, 'd)
           service ->
  (server_params -> 'a -> unit -> page) ->
  ('a, unit, [ `Internal_Service of [ `Local_Service ] ], 'b, 'c, 'd) service

val register_new_state_url_for_session :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'b, 'c, 'd)
           service ->
  (server_params -> 'a -> unit -> page) ->
  ('a, unit, [ `Internal_Service of [ `Local_Service ] ], 'b, 'c, 'd) service

val new_post_url :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c,
            unit name)
           service ->
  post_params:('d, [ `WithoutSuffix ], 'e) params_type ->
  ('a, 'd, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, 'e) service

val new_post_state_url :
  fallback:('a, 'b, [ `Internal_Service of [ `Public_Service ] ], 'c, 'd, 'e) service ->
  post_params:('f, [ `WithoutSuffix ], 'g) params_type ->
  ('a, 'f, [ `Internal_Service of [ `Local_Service ] ], 'c, 'd, 'g) service

val register_new_post_url :
  fallback:('a, unit, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'b, 'c, unit name)
           service ->
  post_params:('d, [ `WithoutSuffix ], 'e) params_type ->
  (server_params -> 'a -> 'd -> page) ->
  ('a, 'd, [ `Internal_Service of [ `Public_Service ] ], 'b, 'c, 'e) service

val register_new_post_state_url :
  fallback:('a, 'b, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'c, 'd, 'e)
           service ->
  post_params:('f, [ `WithoutSuffix ], 'g) params_type ->
  (server_params -> 'a -> 'f -> page) ->
  ('a, 'f, [ `Internal_Service of [ `Local_Service ] ], 'c, 'd, 'g) service

val register_new_post_state_url_for_session :
  fallback:('a, 'b, [ `Internal_Service of [ `Public_Service ] ],
            [< `WithSuffix | `WithoutSuffix ] as 'c, 'd, 'e)
           service ->
  post_params:('f, [ `WithoutSuffix ], 'g) params_type ->
  (server_params -> 'a -> 'f -> page) ->
  ('a, 'f, [ `Internal_Service of [ `Local_Service ] ], 'c, 'd, 'g) service

val new_actionurl :
  post_params:('a, [ `WithoutSuffix ], 'b) params_type -> ('a, 'b) action

val register_actionurl :
  actionurl:('a, 'b) action ->
  action:(server_params -> 'a -> unit) -> unit

val register_actionurl_for_session :
  actionurl:('a, 'b) action ->
  action:(server_params -> 'a -> unit) -> unit

val register_new_actionurl :
  post_params:('a, [ `WithoutSuffix ], 'b) params_type ->
  action:(server_params -> 'a -> unit) -> ('a, 'b) action

val register_new_actionurl_for_session :
  post_params:('a, [ `WithoutSuffix ], 'b) params_type ->
  action:(server_params -> 'a -> unit) -> ('a, 'b) action
*)
