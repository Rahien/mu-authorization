defmodule Acl do
  require Logger
  require ALog

  @moduledoc """
  Acl allows you to define and verify Access Control Lists.  It is
  used to specify who can see what, and where it should be updated.

  Acl may provide multiple strategies for shielding data.  In order to
  do so, we identified multiple issues to tackle:

  - When can you access a group?
  - What are the graphs of a group?
  - How do we identify a group for future caching?
  - How do we apply constraints?
  - ...

  A current example of applicable access rights can be found in
  Acl.UserGroups.Config
  """
  def process_quads_for_update( quads, _, :sudo ) do
    { [], quads }
  end
  def process_quads_for_update( quads, user_groups, authorization_groups ) do
    # The active_group_names should not consist of an array of strings.

    ALog.di user_groups, "User groups for quad update"
    ALog.di authorization_groups, "Authorization groups for quad update"

    active_groups_info =
      active_user_groups_info( user_groups, authorization_groups )

    all_group_specs =
        active_groups_info
        |> Enum.unzip
        |> elem(1)
        |> List.flatten
        |> Enum.uniq

    resulting_quads =
      active_groups_info
      |> ALog.di( "Active Groups Info" )
      |> Enum.reduce( quads, fn ({active_group, active_group_specs} , acc) ->
        ALog.di( active_group, "Processing quads through active group" )
        ALog.di( Process.info(self(), :current_stacktrace), "Stack trace process_quads_for_update" )
        # active_group_spec should be an array of specs
        Enum.reduce( active_group_specs, acc,
          &Acl.GroupSpec.Protocol.process( active_group, &1, &2 ) )
      end )
      |> ALog.di( "Resulting quads" )

    { all_group_specs, resulting_quads }
  end

  @doc """
  Yields the new query, and all the accessibility groups from which
  this query was constructed.
  """
  def process_query( query, _, :sudo ) do
    { query, [] }
  end
  def process_query( query, user_groups, authorization_groups ) do
    clean_query = Manipulators.SparqlQuery.remove_graph_statements( query )

    active_user_groups_info( user_groups, authorization_groups )
    |> ALog.di( "Active User Groups Info" )
    |> Enum.reduce( { clean_query, [] }, fn ({user_group, ug_access_infos}, { query, access_infos } ) ->
      { new_query, new_access_info } =
        Enum.reduce( ug_access_infos, { query, access_infos },
          fn ( access_info, { query, access_infos } ) ->
            { new_query, new_access_info } = Acl.GroupSpec.Protocol.process_query( user_group, access_info, query )
            { new_query, new_access_info ++ access_infos }
          end )

      { new_query, new_access_info ++ access_infos }
    end)
  end

  def active_user_groups_info( user_groups, authorization_groups ) do
    ALog.di( authorization_groups, "Authorization groups" )
    ALog.di( user_groups, "User groups" )

    authorization_groups_by_name = if authorization_groups do
      authorization_groups
      |> Enum.group_by( &elem( &1, 0 ) )
    else
      %{}
    end

    user_groups
    |> Enum.flat_map( fn (user_group) ->
      if Map.has_key?( authorization_groups_by_name, user_group.name ) do
        [ { user_group, Map.get( authorization_groups_by_name, user_group.name ) } ]
      else
        []
      end

      # Map.get( authorization_groups_by_name, user_group.name, [] )
      # |> Enum.map( fn ({_user_group,_arguments} = user_group_info) -> { user_group, user_group_info } end )
    end )
  end

  @doc """
  Yields the authorization groups to which the current user would have
  access.  This content may be cached.
  """
  def user_authorization_groups( user_groups, request ) do
    user_groups
    |> Enum.map( &({&1,Acl.GroupSpec.Protocol.accessible?(&1, request)}) )
    |> ALog.di( "Accessibility Info" )
    |> Enum.filter( fn
      ({_, {:ok, _}}) -> true
      ({_, {:fail}}) -> false
    end )
    |> ALog.di( "Accessible Group Specs" )
    |> Enum.flat_map( fn ({_,{_,group_infos}}) -> group_infos end )
    |> ALog.di( "User Authorization Groups" )
  end


end
