alias Acl.Accessibility.Protocol, as: APr
alias Acl.GroupSpec.Protocol, as: GPr

defprotocol Acl.GroupSpec.Protocol do
  @type t :: struct()
  @type query :: struct()
  @type request :: struct()
  @type user_group :: {String.t, [String.t]} # this shouldn't be named user_group but user_group_info or something of the likes.  It contains the user_group name and its corresponding variables.

  @doc """
  Indicates whether or not the given group_spec is accessible for the
  current user.  This item could be cached in the future based on the
  accessibility response.
  """
  @spec accessible?( GPr.t, GPr.request ) :: { :ok, [GPr.user_group] } | false
  def accessible?( group_spec, request )

  @doc """
  Processing of a set of quads is hanlded by this method.  It
  transforms the supplied set of quads to a new set of quads.
  """
  @spec process( GPr.t, APr.user_group, [Quad] ) :: [Quad]
  def process( group_spec, user_group, quads )

  @doc """
  Rewrites a SPARQL GET query so it matches the required access
  rights.  In practice, this boils down to rewriting the query so only
  allowed graphs will be queried.

  The returned array of APr.user_group contains all of the user groups
  which could have added content to the response.  An empty array
  means no response could be supplied by this processing.
  """
  @spec process_query( GPr.t, APr.user_group, GPr.query ) :: { GPr.query, [APr.user_group] }
  def process_query( group_spec, user_group, query )
end
