defmodule DSpace.API.UserTest do
  use DSpace.API.Case, async: true

  alias DSpace.API.User

  describe "retrieving a user by UUID" do
    test "returns user when it exists", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"
      user_fixture = load_fixture("fetch_user.json")

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/#{uuid}", fn conn ->
        respond_with_json(conn, 200, user_fixture)
      end)

      {:ok, result} = uuid |> User.fetch() |> API.request(api)

      assert_valid_dspace_resource(result, "eperson", ["name", "email", "metadata"])
      assert result["uuid"] == uuid
    end
  end

  describe "retrieving multiple users" do
    test "lists users with pagination support", %{sham: sham, api: api} do
      users_fixture = load_fixture("fetch_users.json")

      Sham.expect_once(sham, "GET", "/api/eperson/epersons", fn conn ->
        respond_with_json(conn, 200, users_fixture)
      end)

      {:ok, result} = API.request(User.list(), api)

      {users, metadata, next_url} = result
      assert_valid_paginated_response({users, metadata, next_url})
      assert length(users) == 3

      first_user = Enum.at(users, 0)
      assert_valid_dspace_resource(first_user, "eperson")
    end

    test "supports custom pagination parameters", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/eperson/epersons", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "2"
        assert params["size"] == "10"

        respond_with_json(conn, 200, ~s({
          "_embedded": {"epersons": []},
          "_links": {},
          "page": {"size": 10, "totalElements": 0, "totalPages": 0, "number": 2}
        }))
      end)

      {:ok, result} = [page: 2, size: 10] |> User.list() |> API.request(api)

      {_users, metadata, _next_url} = result
      assert metadata["page"]["number"] == 2
      assert metadata["page"]["size"] == 10
    end
  end

  describe "searching for users by email" do
    test "finds user by email address", %{sham: sham, api: api} do
      email = "john.doe@example.com"
      user_fixture = load_fixture("fetch_user.json")

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/search/byEmail", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["email"] == email

        respond_with_json(conn, 200, user_fixture)
      end)

      {:ok, result} = email |> User.fetch_by_email() |> API.request(api)

      assert_valid_dspace_resource(result, "eperson")
      assert result["email"] == email
    end

    test "returns empty map when no user is found", %{sham: sham, api: api} do
      email = "nonexistent@example.com"

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/search/byEmail", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["email"] == email

        conn
        |> Plug.Conn.put_resp_content_type("application/hal+json")
        |> Plug.Conn.resp(204, "")
      end)

      {:ok, result} = email |> User.fetch_by_email() |> API.request(api)

      assert result == %{}
    end
  end

  describe "searching for users by metadata" do
    test "searches across user metadata fields", %{sham: sham, api: api} do
      query = "john doe"
      users_fixture = load_fixture("fetch_users.json")

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/search/byMetadata", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["query"] == query

        respond_with_json(conn, 200, users_fixture)
      end)

      {:ok, result} = [query: query] |> User.find() |> API.request(api)
      {users, _metadata, _next_url} = result
      first_user = Enum.at(users, 0)

      assert first_user["email"] == "john.doe@example.com"
      assert Map.has_key?(first_user, "uuid")
    end

    test "supports pagination in metadata search", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/eperson/epersons/search/byMetadata", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["query"] == "search term"
        assert params["page"] == "1"
        assert params["size"] == "5"

        respond_with_json(conn, 200, ~s({
          "_embedded": {"epersons": []},
          "_links": {},
          "page": {"size": 5, "totalElements": 0, "totalPages": 0, "number": 1}
        }))
      end)

      {:ok, result} = [query: "search term", page: 1, size: 5] |> User.find() |> API.request(api)
      {_users, metadata, _next_url} = result

      assert metadata["page"]["number"] == 1
      assert metadata["page"]["size"] == 5
    end

    test "searches by UUID for exact match", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"
      user_data = test_single_user_in_list(uuid)

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/search/byMetadata", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["query"] == uuid

        respond_with_json(conn, 200, user_data)
      end)

      {:ok, result} = [query: uuid] |> User.find() |> API.request(api)
      {users, _metadata, _next_url} = result

      assert length(users) == 1
      assert Enum.at(users, 0)["uuid"] == uuid
    end
  end

  describe "creating users" do
    test "creates user", %{sham: sham, api: api} do
      user_data =
        test_user_data(%{
          "name" => "newuser@example.com",
          "email" => "newuser@example.com",
          "metadata" => %{
            "eperson.firstname" => [%{"value" => "New", "authority" => "", "confidence" => -1}],
            "eperson.lastname" => [%{"value" => "User", "authority" => "", "confidence" => -1}]
          }
        })

      user_fixture = load_fixture("fetch_user.json")

      Sham.expect_once(sham, "POST", "/api/eperson/epersons", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert request_data["email"] == "newuser@example.com"
        assert request_data["name"] == "newuser@example.com"
        assert request_data["canLogIn"] == true
        assert request_data["type"] == "eperson"

        respond_with_json(conn, 201, user_fixture)
      end)

      {:ok, result} = user_data |> User.create() |> API.request(api)

      assert_valid_dspace_resource(result, "eperson")
      assert result["uuid"] == "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"
    end

    test "handles duplicate email address error", %{sham: sham, api: api} do
      user_data = test_user_data(%{"email" => "existing@example.com"})

      Sham.expect_once(sham, "POST", "/api/eperson/epersons", fn conn ->
        respond_with_json(conn, 422, ~s({
          "status": 422,
          "message": "Email address already exists"
        }))
      end)

      {:error, error} = user_data |> User.create() |> API.request(api)

      assert error.status == 422
    end
  end

  describe "modifying existing users" do
    test "updates user metadata with patch operations", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      update_operations = [
        %{
          "op" => "replace",
          "path" => "/metadata/eperson.firstname/0/value",
          "value" => %{"value" => "Jane"}
        },
        %{
          "op" => "replace",
          "path" => "/metadata/eperson.lastname/0/value",
          "value" => %{"value" => "Smith"}
        }
      ]

      Sham.expect_once(sham, "PATCH", "/api/eperson/epersons/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert length(request_data) == 2
        first_op = Enum.at(request_data, 0)
        assert first_op["op"] == "replace"
        assert first_op["path"] == "/metadata/eperson.firstname/0/value"

        respond_with_json(conn, 200, ~s({
          "uuid": "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e",
          "name": "jane.smith@example.com",
          "email": "jane.smith@example.com",
          "type": "eperson"
        }))
      end)

      {:ok, result} = uuid |> User.update(update_operations) |> API.request(api)

      assert result["uuid"] == uuid
      assert result["name"] == "jane.smith@example.com"
    end

    test "updates administrative properties", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      # Test updating certificate requirement
      cert_operations = [
        %{"op" => "replace", "path" => "/certificate", "value" => true}
      ]

      Sham.expect_once(sham, "PATCH", "/api/eperson/epersons/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        operation = List.first(request_data)
        assert operation["path"] == "/certificate"
        assert operation["value"] == true

        respond_with_json(conn, 200, ~s({
          "uuid": "#{uuid}",
          "requireCertificate": true,
          "type": "eperson"
        }))
      end)

      {:ok, result} = uuid |> User.update(cert_operations) |> API.request(api)
      assert result["requireCertificate"] == true
    end

    test "updates login capability", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      login_operations = [
        %{"op" => "replace", "path" => "/canLogin", "value" => false}
      ]

      Sham.expect_once(sham, "PATCH", "/api/eperson/epersons/#{uuid}", fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        operation = List.first(request_data)
        assert operation["path"] == "/canLogin"
        assert operation["value"] == false

        respond_with_json(conn, 200, ~s({
          "uuid": "#{uuid}",
          "canLogIn": false,
          "type": "eperson"
        }))
      end)

      {:ok, result} = uuid |> User.update(login_operations) |> API.request(api)
      assert result["canLogIn"] == false
    end

    test "updates email address", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      email_operations = [
        %{"op" => "replace", "path" => "/email", "value" => "newemail@example.com"}
      ]

      Sham.expect_once(sham, "PATCH", "/api/eperson/epersons/#{uuid}", fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        operation = List.first(request_data)
        assert operation["path"] == "/email"
        assert operation["value"] == "newemail@example.com"

        respond_with_json(conn, 200, ~s({
          "uuid": "#{uuid}",
          "email": "newemail@example.com",
          "name": "newemail@example.com",
          "type": "eperson"
        }))
      end)

      {:ok, result} = uuid |> User.update(email_operations) |> API.request(api)
      assert result["email"] == "newemail@example.com"
    end

    test "replaces entire user content", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      user_data =
        test_user_data(%{
          "email" => "replaced@example.com",
          "name" => "replaced@example.com",
          "metadata" => %{
            "eperson.firstname" => [%{"value" => "Replaced"}],
            "eperson.lastname" => [%{"value" => "User"}]
          }
        })

      Sham.expect_once(sham, "PUT", "/api/eperson/epersons/#{uuid}", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request_data = JSON.decode!(body)

        assert request_data["email"] == "replaced@example.com"

        respond_with_json(conn, 200, ~s({
          "uuid": "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e",
          "name": "replaced@example.com",
          "email": "replaced@example.com",
          "type": "eperson"
        }))
      end)

      {:ok, result} = uuid |> User.replace(user_data) |> API.request(api)

      assert result["uuid"] == uuid
      assert result["email"] == "replaced@example.com"
    end
  end

  describe "removing users" do
    test "deletes user successfully", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      Sham.expect_once(sham, "DELETE", "/api/eperson/epersons/#{uuid}", fn conn ->
        respond_with_json(conn, 204, "")
      end)

      {:ok, result} = uuid |> User.delete() |> API.request(api)

      assert result == :ok
    end
  end

  describe "retrieving user groups" do
    test "retrieves direct group membership", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"
      groups_fixture = load_fixture("fetch_groups.json")

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/#{uuid}/groups", fn conn ->
        respond_with_json(conn, 200, groups_fixture)
      end)

      {:ok, result} = uuid |> User.list_groups() |> API.request(api)

      {groups, metadata, next_url} = result
      assert_valid_paginated_response({groups, metadata, next_url})
      assert length(groups) == 3

      first_group = Enum.at(groups, 0)
      assert Map.has_key?(first_group, "uuid")
      assert Map.has_key?(first_group, "name")
      assert first_group["type"] == "group"
      assert first_group["name"] == "Administrators"
      assert first_group["permanent"] == true

      assert metadata["page"]["totalElements"] == 3
      assert is_nil(next_url)
    end

    test "supports custom pagination parameters for groups", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/#{uuid}/groups", fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["page"] == "1"
        assert params["size"] == "25"

        respond_with_json(conn, 200, ~s({
          "_embedded": {"groups": []},
          "_links": {},
          "page": {"size": 25, "totalElements": 0, "totalPages": 0, "number": 1}
        }))
      end)

      {:ok, result} = uuid |> User.list_groups(page: 1, size: 25) |> API.request(api)

      {_groups, metadata, _next_url} = result
      assert metadata["page"]["number"] == 1
      assert metadata["page"]["size"] == 25
    end
  end

  describe "edge cases and error handling" do
    test "handles server errors gracefully", %{sham: sham, api: api} do
      uuid = "8a010aaa-e8cb-44e3-b24a-b9df8be5bd0e"

      Sham.expect_once(sham, "GET", "/api/eperson/epersons/#{uuid}", fn conn ->
        respond_with_json(conn, 500, ~s({
          "timestamp": "2023-10-15T12:00:00.000+00:00",
          "status": 500,
          "error": "Internal Server Error",
          "message": "An error occurred"
        }))
      end)

      {:error, error} = uuid |> User.fetch() |> API.request(api)

      assert error.status == 500
    end

    test "handles authorization errors", %{sham: sham, api: api} do
      Sham.expect_once(sham, "GET", "/api/eperson/epersons/search/byMetadata", fn conn ->
        respond_with_json(conn, 403, ~s({
          "timestamp": "2023-10-15T12:00:00.000+00:00",
          "status": 403,
          "error": "Forbidden",
          "message": "Access denied. Only administrators can search users."
        }))
      end)

      {:error, error} = [query: "test"] |> User.find() |> API.request(api)

      assert error.status == 403
    end
  end

  # Private helpers

  defp test_user_data(overrides) do
    base_data = %{
      "name" => "test@example.com",
      "email" => "test@example.com",
      "canLogIn" => true,
      "requireCertificate" => false,
      "selfRegistered" => false,
      "type" => "eperson",
      "metadata" => %{
        "eperson.firstname" => [%{"value" => "Test", "authority" => "", "confidence" => -1}],
        "eperson.lastname" => [%{"value" => "User", "authority" => "", "confidence" => -1}]
      }
    }

    Map.merge(base_data, overrides)
  end

  defp test_single_user_in_list(uuid) do
    ~s({
      "_embedded": {
        "epersons": [
          {
            "id": "#{uuid}",
            "uuid": "#{uuid}",
            "name": "user@example.com",
            "email": "user@example.com",
            "type": "eperson"
          }
        ]
      },
      "_links": {},
      "page": {"size": 20, "totalElements": 1, "totalPages": 1, "number": 0}
    })
  end
end
