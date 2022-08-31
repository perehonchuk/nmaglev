#!/usr/bin/env escript
%% -*- erlang -*-
%%! -sname factorial -mnesia debug verbose
main([_]) ->
    Terms = consult_root(),
    Terms1 = append_eqwalizer_deps(Terms),
    [io:format("~p.~n", [T]) || T <- Terms1].

-define(DEFAULT_CONFIG_FILE, "rebar.config").
-define(PRV_ERROR(Reason),
        {error, {?MODULE, Reason}}).
%% ===================================================================
%% Public API
%% ===================================================================

append_eqwalizer_deps(Terms) ->
    Terms1 = [append_deps(T) || T <- Terms],
    Terms2 = case lists:keyfind(deps, 1, Terms1) of
        false -> lists:append(Terms1, [{deps, append_dep([])}]);
        _ -> Terms1
    end,
    case lists:keyfind(project_plugins, 1, Terms2) of
        false -> lists:append(Terms2, [{project_plugins, append_plugin([])}]);
        _ -> Terms2
    end.
append_deps({deps, Deps}) ->
    case lists:keyfind(eqwalizer_support, 1, Deps) of
        false -> 
            {deps, append_dep(Deps)};
        _ -> 
            {deps, Deps}
    end;
append_deps({project_plugins, Plugins}) ->
    case lists:keyfind(eqwalizer_rebar3, 1, Plugins) of
        false -> 
            {project_plugins, append_plugin(Plugins)};
        _ -> 
            {project_plugins, Plugins}
    end;
append_deps(A) ->
    A.

append_dep(Deps) ->
    lists:append(Deps, [
                {
                    eqwalizer_support, {
                        git_subdir, 
                        "https://github.com/whatsapp/eqwalizer.git",
                        {branch, "main"},
                        "eqwalizer_support"
                    }
                }
            ]).
append_plugin(Plugins) ->
    lists:append(Plugins, [
                {
                    eqwalizer_rebar3, {
                        git_subdir, 
                        "https://github.com/whatsapp/eqwalizer.git",
                        {branch, "main"},
                        "eqwalizer_rebar3"
                    }
                }
            ]).
%% @doc reads the default config file at the top of a full project
-spec consult_root() -> [any()].
consult_root() ->
    consult_file(config_file()).

%% @doc reads the default config file in a given directory.
-spec consult(file:name()) -> [any()].
consult(Dir) ->
    consult_file(filename:join(Dir, ?DEFAULT_CONFIG_FILE)).



%% @doc reads a given config file, including the `.script' variations,
%% if any can be found, and asserts that the config format is in
%% a key-value format.
-spec consult_file(file:filename()) -> [{_,_}].
consult_file(File) ->
    Terms = consult_file_(File),
    true = verify_config_format(Terms),
    Terms.

%% @private reads a given file; if the file has a `.script'-postfixed
%% counterpart, it is evaluated along with the original file.
-spec consult_file_(file:name()) -> [any()].
consult_file_(File) when is_binary(File) ->
    consult_file_(binary_to_list(File));
consult_file_(File) ->
    case filename:extension(File) of
        ".script" ->
            {ok, Terms} = consult_and_eval(remove_script_ext(File), File),
            Terms;
        _ ->
            Script = File ++ ".script",
            case filelib:is_regular(Script) of
                true ->
                    {ok, Terms} = consult_and_eval(File, Script),
                    Terms;
                false ->
                    try_consult(File)
            end
    end.

%% @private checks that a list is in a key-value format.
%% Raises an exception in any other case.
-spec verify_config_format([{_,_}]) -> true.
verify_config_format([]) ->
    true;
verify_config_format([{_Key, _Value} | T]) ->
    verify_config_format(T);
verify_config_format([Term | _]) ->
    throw(?PRV_ERROR({bad_config_format, Term})).

%% ===================================================================
%% Internal functions
%% ===================================================================

%% @private consults a consult file, then executes its related script file
%% with the data returned from the consult.
-spec consult_and_eval(File::file:name_all(), Script::file:name_all()) ->
                              {ok, Terms::[term()]} |
                              {error, Reason::term()}.
consult_and_eval(File, Script) ->
    StateData = try_consult(File),
    %% file:consult/1 always returns the terms as a list, however file:script
    %% can (and will) return any kind of term(), to make consult_and_eval
    %% work the same way as eval we ensure that when no list is returned we
    %% convert it in a list.
    case file:script(Script, bs([{'CONFIG', StateData}, {'SCRIPT', Script}])) of
        {ok, Terms} when is_list(Terms) ->
            {ok, Terms};
        {ok, Term} ->
            {ok, [Term]};
        Error ->
            Error
    end.

%% @private drops the .script extension from a filename.
-spec remove_script_ext(file:filename()) -> file:filename().
remove_script_ext(F) ->
    filename:rootname(F, ".script").

%% @private sets up bindings for evaluations from a KV list.
-spec bs([{_,_}]) -> erl_eval:binding_struct().
bs(Vars) ->
    lists:foldl(fun({K,V}, Bs) ->
                        erl_eval:add_binding(K, V, Bs)
                end, erl_eval:new_bindings(), Vars).



%% @private returns the name/path of the default config file, or its
%% override from the OS ENV var `REBAR_CONFIG'.
-spec config_file() -> file:filename().
config_file() ->
    case os:getenv("REBAR_CONFIG") of
        false ->
            ?DEFAULT_CONFIG_FILE;
        ConfigFile ->
            ConfigFile
    end.

try_consult(File) ->
    case file:consult(File) of
        {ok, Terms} ->
            Terms;
        {error, enoent} ->
            [];
        {error, Reason} ->
            throw(?PRV_ERROR({bad_term_file, File, Reason}))
    end.
