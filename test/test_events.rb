require 'helper'

class EventsTest < Scalyr::ScalyrOutTest

  def test_format
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )
    mock.should_receive( :post_request ).with_any_args.and_return( response )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.emit( { "a" => 1 }, time )
    d.expect_format [ "test", time, { "a" => 1 } ].to_msgpack
    d.run
  end

  def test_build_add_events_body_basic_values
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "a" => 1 }
    d.emit( attrs, time )

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        assert( body.key?( "token" ), "Missing token field"  )
        assert( body.key?( "client_timestamp" ), "Missing client_timestamp field" )
        assert( body.key?( "session" ), "Missing session field" )
        assert( !body.key?( "sessionInfo"), "sessionInfo field set, but no sessionInfo" )
        assert( body.key?( "events" ), "missing events field" )
        assert( body.key?( "threads" ), "missing threads field" )
        assert_equal( 1, body['events'].length, "Only expecting 1 event" )
        assert_equal( d.instance.to_nanos( time ), body['events'][0]['ts'].to_i, "Event timestamp differs" )
        assert_equal( attrs, body['events'][0]['attrs'], "Value of attrs differs from log" )
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_with_session_info
    d = create_driver CONFIG + 'session_info { "test":"value" }'

    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "a" => 1 }
    d.emit( attrs, time )

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        assert( body.key?( "sessionInfo"), "sessionInfo field set, but no sessionInfo" )
        assert_equal( "value", body["sessionInfo"]["test"] )
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_incrementing_timestamps
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.emit( { "a" => 1 }, time )
    d.emit( { "a" => 2 }, time )

    time = Time.parse("2015-04-01 09:59:00 UTC").to_i
    d.emit( { "a" => 3 }, time )

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        events = body['events']
        assert_equal( 3, events.length, "Expecting 3 events" )
        #test equal timestamps are increased
        assert events[1]['ts'].to_i > events[0]['ts'].to_i, "Event timestamps must increase"

        #test earlier timestamps are increased
        assert events[2]['ts'].to_i > events[1]['ts'].to_i, "Event timestamps must increase"
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_thread_ids
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.tag = "test1"
    d.emit( { "a" => 1 }, time )

    #fluentd testing doesn't have an easy way to test multiple tags
    #for a single run so just test the one for now
    
    #d.tag = "test2"
    #d.emit( { "a" => 2 }, time )

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        events = body['events']
        threads = body['threads']

        assert_equal( 1, threads.length, "Expecting 1 thread, #{threads.length} found" )
        assert_equal( 1, events.length, "Expecting 1 event, #{events.length} found" )
        assert_equal( events[0]['thread'], threads[0]['id'].to_s, "thread id should match event thread id" )
      }
      ).and_return( response )

    d.run
  end

end
