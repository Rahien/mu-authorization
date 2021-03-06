alias SparqlServer.Router.HandlerSupport, as: Support

defmodule SparqlServer.Router do
  @moduledoc """
  The router for the SPARQL endpoint.
  """
  use Plug.Router
  require Logger
  require ALog

  plug :match
  plug :dispatch

  def init(args) do
    args
  end


  ################
  ### Routing code

  post "/sparql" do
    {:ok, body, _} = read_body(conn)

    ALog.di conn, "Received POST connection"
    conn = downcase_request_headers( conn )
    debug_log_request_id( conn )

    { method, query } = get_query_from_post( conn, body ) |> ALog.di( "Received query" )

    Support.handle_query query, method, conn
    |> send_sparql_response
  end

  get "/sparql" do
    params = conn.query_string |> URI.decode_query

    ALog.di conn, "Received GET connection"
    conn = downcase_request_headers( conn )
    debug_log_request_id( conn )

    query = params["query"]

    Support.handle_query query, :query, conn
    |> send_sparql_response
  end

  match _, do: send_resp(conn, 404, "404 error not found")


  ################
  ### Internal logic

  defp get_query_from_post( conn, body ) do
    if Plug.Conn.get_req_header(conn, "content-type") == ["application/sparql-update"] do
      { :update, body }
    else
      body_params = URI.decode_query( body )
      cond do
        body_params["query"] -> { :any, body_params["query"] } # apparently this can be both :query as well as :update in practice
        body_params["update"] -> { :update, body_params["update"] }
        true ->
          params =
            conn.query_string
            |> URI.decode_query
          { :any, params["query"] }
      end
    end
  end

  defp downcase_request_headers( conn ) do
    new_request_headers =
      conn
      |> Map.get(:req_headers)
      |> Enum.map( fn {name, val} -> { String.downcase( name ), val } end )

    conn
    |> Map.put( :req_headers, new_request_headers )
  end

  ### Sends the supplied results on the connection, setting the
  ### necessary header and response type.
  defp send_sparql_response( { conn, response } ) do
    conn
    |> put_resp_content_type( "application/sparql-results+json" )
    |> send_resp(200, response)
  end

  ### Allows us to debug log the request id.  Currently doesn't
  ### execute any code.
  defp debug_log_request_id( _conn ) do
    # conn
    # |> Plug.Conn.get_req_header( "mu-session-id" )
    # |> List.first
    # |> ALog.di( "session id" )
  end



end
