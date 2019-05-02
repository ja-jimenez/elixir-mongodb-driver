defmodule Mongo.ChangeStreamTest do
  use ExUnit.Case # DO NOT MAKE ASYNCHRONOUS

  setup_all do
    assert {:ok, top} = Mongo.TestConnection.connect
    assert {:ok, %Mongo.InsertOneResult{}} = Mongo.insert_one(top, "users", %{name: "Waldo"})
    %{pid: top}
  end

  def consumer_1(top, monitor) do
    cursor = Mongo.watch_collection(top, "users", [], fn doc -> IO.puts("Token #{inspect doc}"); send(monitor, {:token, doc}) end, max_time: 1_000, debug: true )
    result = cursor |> Enum.take(2) |> Enum.at(0)
    send(monitor, {:insert, result})
  end

  def consumer_2(top, monitor, token) do
    cursor = Mongo.watch_collection(top, "users", [], fn doc -> IO.puts("Token #{inspect doc}"); send(monitor, {:token, doc}) end, resume_after: token, max_time: 1_000 )
    result = cursor |> Enum.take(1) |> Enum.at(0)
    send(monitor, {:insert, result})
  end

  def consumer_3(top, monitor, token) do
    cursor = Mongo.watch_collection(top, "users", [], fn doc -> IO.puts("Token #{inspect doc}"); send(monitor, {:token, doc}) end, resume_after: token, max_time: 1_000 )
    result = cursor |> Enum.take(4) |> Enum.map(fn %{"fullDocument" => %{"name" => name}} -> name end)
    send(monitor, {:insert, result})

  end

  def producer(top) do
    Process.sleep(300)
    assert {:ok, %Mongo.InsertOneResult{}} = Mongo.insert_one(top, "users", %{name: "Greta"})
    assert {:ok, %Mongo.InsertOneResult{}} = Mongo.insert_one(top, "users", %{name: "Gustav"})
    assert {:ok, %Mongo.InsertOneResult{}} = Mongo.insert_one(top, "users", %{name: "Tom"})
  end

  @tag :change_streams
  test "change stream: watch and resume_after", %{pid: top} do

    me = self()
    spawn(fn -> consumer_1(top, me) end)
    spawn(fn -> producer(top) end)

    assert_receive {:token, nil}, 2_000
    assert_receive {:token, token}, 2_000
    assert_receive {:insert, %{"fullDocument" => %{"name" => "Greta"}}}, 2_000

    Process.sleep(500)

    assert {:ok, %Mongo.InsertOneResult{}} = Mongo.insert_one(top, "users", %{name: "Liese"})

    spawn(fn -> consumer_2(top, me, token) end)
    spawn(fn -> producer(top) end)

    assert_receive {:token, _}, 2_000
    assert_receive {:insert, %{"fullDocument" => %{"name" => "Gustav"}}}, 2_000

    Process.sleep(500)

    spawn(fn -> consumer_3(top, me, token) end)
    spawn(fn -> producer(top) end)

    assert_receive {:token, _}, 2_000
    assert_receive {:insert, ["Gustav", "Tom", "Liese", "Greta"]}, 2_000

  end
end
