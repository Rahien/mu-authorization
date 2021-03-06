alias Acl.UserGroups.Config, as: Config

defmodule Acl.UserGroups do
  @doc """
  Filters the useage_groups for a particular useage.
  """
  def user_groups_for( user_groups, useage ) do
    user_groups
    |> Enum.filter( fn (user_group) ->
      user_group
      |> Map.get( :useage )
      |> Enum.member?( useage )
    end )
  end

  @doc """
  Yields all the user groups for the supplied useage.
  """
  def for_use( useage ) do
    Config.user_groups
    |> user_groups_for( useage )
  end
end
