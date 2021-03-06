alias SparqlServer.Router.AccessGroupSupport, as: AccessGroupSupport

defmodule SparqlServer.Router.HandlerSupport do
  require Logger
  require ALog

  @doc """
  Handles the processing of a query.  Calculating the response whilst
  possibly getting some contents from the connection.  The new
  connection (to which the response may be sent) is yielded back,
  together with the response which should be set on the client.
  """
  def handle_query(query, kind, conn) do
    top_level_key = case kind do
                      :query -> :QueryUnit
                      :update -> :UpdateUnit
                      :any -> :Sparql
                    end

    parsed_form =
      query
      |> ALog.di( "Raw received query" )
      |> String.trim
      |> String.replace( "\r", "" ) # TODO: check if this is valid and/or ensure parser skips \r between words.
      |> Parser.parse_query_full( top_level_key )
      |> ALog.di( "Parsed query" )
      |> wrap_query_in_toplevel
      |> ALog.di( "Wrapped parsed query" )

    { conn, new_parsed_forms } =
      if is_select_query( parsed_form ) do
        manipulate_select_query( parsed_form, conn )
      else
        manipulate_update_query( parsed_form, conn )
      end

    encoded_response =
      new_parsed_forms
      |> ALog.di( "New parsed forms" )
      |> Enum.reduce( true, fn( elt, _ ) ->
        elt
        |> Regen.result
        |> ALog.di( "Posing query to backend" )
        |> SparqlClient.query
        end )
      |> Poison.encode!

    { conn, encoded_response }
  end

  def wrap_query_in_toplevel( %InterpreterTerms.SymbolMatch{ symbol: :Sparql } = matched ) do
    matched
  end
  def wrap_query_in_toplevel( %InterpreterTerms.SymbolMatch{ string: str } = matched ) do
    # Only public for benchmark
    %InterpreterTerms.SymbolMatch{
      symbol: :Sparql,
      string: str,
      submatches: [matched]
    }
  end

  @doc """
  Yields non-nil iff the query is a select query.
  """
  def is_select_query( query ) do
    case query do
      %InterpreterTerms.SymbolMatch{
        symbol: :Sparql,
        submatches: [
          %InterpreterTerms.SymbolMatch{
            symbol: :QueryUnit} ]} -> true
      _ -> false
    end
  end


  ### Manipulates the select query yielding back the valid set of
  ### queries which should be executed on the database.
  defp manipulate_select_query( query, conn ) do
    { conn, authorization_groups } = AccessGroupSupport.calculate_access_groups( conn )

    # TODO: apply Acl.UserGroups.Config to select queries
    { conn, query } = if authorization_groups == :sudo do
      { conn, query }
    else
      { query, _access_groups } =
        query
        |> Manipulators.SparqlQuery.remove_from_statements # TODO: check how BaseDecl should be interpreted, possibly also remove that.
        |> Acl.process_query( Acl.UserGroups.for_use(:read), authorization_groups )

      conn = AccessGroupSupport.put_access_groups( conn, authorization_groups )
      { conn, query }
    end

    { conn, [ query ] }
  end

  ### Manipulates the update query yielding back the valid set of
  ### queries which should be executed on the database.
  defp manipulate_update_query( query, conn ) do
    Logger.debug( "This is an update query" )

    { conn, authorization_groups } = AccessGroupSupport.calculate_access_groups( conn )

    # TODO DRY into/from Updates.QueryAnalyzer.insert_quads

    # TODO: Check where the default_graph is used where these options are passed and verify whether this is a sensible name.
    options = %{
      default_graph: Updates.QueryAnalyzer.Iri.from_iri_string( "<http://mu.semte.ch/application>", %{} ),
      prefixes: %{ "xsd" => Updates.QueryAnalyzer.Iri.from_iri_string("<http://www.w3.org/2001/XMLSchema#>"),
                   "foaf" => Updates.QueryAnalyzer.Iri.from_iri_string("<http://xmlns.com/foaf/0.1/>") }
    }

    executable_queries =
      query
      |> ALog.di( "Parsed query" )
      |> Updates.QueryAnalyzer.quads( %{
          default_graph: Updates.QueryAnalyzer.Iri.from_iri_string( "<http://mu.semte.ch/application>", %{} ),
          authorization_groups: authorization_groups } )
      |> Enum.reject( &match?( {_,[]}, &1 ) )
      |> ALog.di( "Non-empty operations" )
      |> Enum.map(
        fn ({statement, quads}) ->
          ALog.di quads, "detected quads"
          ALog.di statement, "quads operation"

          processed_quads = enforce_write_rights( quads, authorization_groups  )

          { statement, processed_quads }
        end)
      |> Delta.publish_updates
      |> Enum.map(
        fn ({statement, processed_quads}) ->
          case statement do
            :insert ->
              Updates.QueryAnalyzer.construct_insert_query_from_quads( processed_quads, options )
            :delete ->
              Updates.QueryAnalyzer.construct_delete_query_from_quads( processed_quads, options )
          end end )

      # TODO should we set the access groups on update queries too?
      # see AccessGroupSupport.put_access_groups/2 ( conn, authorization_groups )
      { conn, executable_queries }
  end

  defp enforce_write_rights( quads, authorization_groups ) do
    Logger.info( "Enforcing write rights")
    user_groups_for_update = Acl.UserGroups.for_use( :write )

    processed_quads =
      quads
      |> Acl.process_quads_for_update( user_groups_for_update, authorization_groups )
      |> elem(1)
      |> ALog.di( "processed quads" )

    processed_quads
  end


end
