--!nonstrict
-- Server entry point. All boot logic (order, failure isolation, status for clients) lives in
-- Boot.luau so the Lune smoke tests boot the server exactly the same way.
require(script.Parent.Boot).run()
