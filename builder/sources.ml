(* virt-builder
 * Copyright (C) 2014 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Common_gettext.Gettext
open Common_utils

open Printf
open Unix

type source = {
  name : string;
  uri : string;
  gpgkey : string option;
}

let parse_conf ~prog ~debug file =
  if debug then (
    eprintf (f_"%s: trying to read %s\n") prog file;
  );
  let sections = Ini_reader.read_ini file in

  let sources = List.fold_right (
    fun (n, fields) acc ->
      let give_source n fields =
        let fields = List.map (fun (k, sk, v) -> (k, sk), v) fields in
        let uri =
          try List.assoc ("uri", None) fields
          with Not_found as ex ->
            eprintf (f_"%s: no 'uri' entry for '%s' in %s, skipping it\n") prog n file;
            raise ex in
        let gpgkey =
          let k =
            try Some (URI.parse_uri (List.assoc ("gpgkey", None) fields)) with
            | Not_found -> None
            | Invalid_argument "URI.parse_uri" as ex ->
              if debug then (
                eprintf (f_"%s: '%s' has invalid gpgkey URI\n") prog n;
              );
              raise ex in
          match k with
          | None -> None
          | Some uri ->
            (match uri.URI.protocol with
            | "file" -> Some uri.URI.path
            | _ ->
              if debug then (
                eprintf (f_"%s: '%s' has non-local gpgkey URI\n") prog n;
              );
              None
            ) in
        {
          name = n; uri = uri; gpgkey = gpgkey;
        }
      in
      try (give_source n fields) :: acc
      with Not_found | Invalid_argument _ -> acc
  ) sections [] in

  if debug then (
    eprintf (f_"%s: ... read %d sources\n") prog (List.length sources);
  );

  sources

let merge_sources current_sources new_sources =
  List.fold_right (
    fun source acc ->
      if List.exists (fun { name = n } -> n = source.name) acc then
        acc
      else
        source :: acc
  ) new_sources current_sources

let filter_filenames filename =
  Filename.check_suffix filename ".conf"

let read_sources ~prog ~debug =
  let dirs = Paths.xdg_config_dirs ~prog in
  let dirs =
    match Paths.xdg_config_home ~prog with
    | None -> dirs
    | Some dir -> dir :: dirs in
  let dirs = List.map (fun x -> x // "repos.d") dirs in
  List.fold_right (
    fun dir acc ->
      let files =
        try List.filter filter_filenames (Array.to_list (Sys.readdir dir))
        with Sys_error _ -> [] in
      let files = List.map (fun x -> dir // x) files in
      List.fold_left (
        fun acc file ->
          try merge_sources acc (parse_conf ~prog ~debug file) with
          | Unix_error (code, fname, _) ->
            if debug then (
              eprintf (f_"%s: file error: %s: %s\n") prog fname (error_message code)
            );
            acc
          | Invalid_argument msg ->
            if debug then (
              eprintf (f_"%s: internal error: invalid argument: %s\n") prog msg
            );
            acc
      ) acc files
  ) dirs []
