module revanth::dapp {
    use std::debug;
    use std::string;
    use std::vector;
    use std::option;

    use aptos_framework::table;
    use aptos_framework::smart_table;

    // error codes
    const E_INVALID_INPUT: u8 = 1;
    const E_PLAYER_ALREADY_JOINED: u8 = 2;

    // Table of Room
    struct RoomsList has key, store {
        rooms_list: vector<Room>,
    }

    // Room
    struct Room has key, store {
        name: string::String,
        grid: vector<vector<Slot>>,
        id: u64,
        moves: table::Table<address,Move>,
        players_list: vector<Player>,
        items_list: vector<Item>,
        inactive: bool,
    }

    // Player (oomp)
    struct Player has key, store {
        address: address,
        inventory: table::Table<u8, u8>,
        position: Move,
    }

    // Item (oomp)
    struct Item has key, store, drop {
        item_code: u8,
        position: Move,
        id: u64,
    }

    // Player ( lowest )
    struct Slot has key, store {
        player: option::Option<PlayerIcon>, 
    }

    // Player Icon ( wow )
    struct PlayerIcon has key, store, drop, copy {
        player_id: u64,
    }

    // Move ( really )
    struct Move has key, store, drop, copy {
        x: u64,
        y: u64,
    }

    // items
    const I_EXIT: u8 = 2;
    const I_KEY: u8 = 3;
    const I_BOX: u8 = 4;
    const I_WON: u8 = 5;

    // directions
    const D_UP: u8 = 1;
    const D_RIGHT: u8 = 2;
    const D_DOWN: u8 = 3;
    const D_LEFT: u8 = 4;

    // size
    const C_SIZE: u8 = 10;
    const C_MAX_PLAYERS: u8 = 5;
    
    /*
    runs only once in lifetime
    */
    fun init_module(account: &signer) {
        move_to<RoomsList>(
            account,
            RoomsList {
                rooms_list: vector::empty<Room>(),
            }
        );
    }

    /*
    Creates a single room and adds it to RoomList
    */
    fun create_room() acquires RoomsList {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = Room {
            name: string::utf8(b"New Room"),
            grid: vector::empty<vector<Slot>>(),
            id: vector::length<Room>(&roomslist.rooms_list),
            moves: table::new<address, Move>(),
            inactive: true,
            players_list: vector::empty<Player>(),
            items_list: vector::empty<Item>(),
        };

        let i = 0;
        let j = 0;

        while(i < C_SIZE) {
            let row = vector::empty<Slot>();

            j = 0;
            while(j < C_SIZE) {
                // create Slot
                vector::push_back(
                    &mut row,
                    Slot {
                        player: option::none<PlayerIcon>(),
                    }
                );

                // Random Item Generation
                // use j, i => x, y

                
                j = j+1;
            };

            vector::push_back(&mut room.grid, row);
            i = i+1;
        };

        

        vector::push_back(&mut roomslist.rooms_list, room);
    }

    /*
    Adds player into the Room Moves Dictionary.
    */
    fun add_player(player_addr: address, room_id: u64) acquires RoomsList {
        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);
        
        let player = Player {
            address: player_addr,
            inventory: table::new<u8, u8>(),
            position: Move {
                x: 0,
                y: 0,
            }
        };

        // add in player list
        vector::push_back(
            &mut room.players_list,
            player,
        );

        // add in PlayerIcon to grid
        let slot = get_slot_mut(&mut room.grid, 0, 0);
        slot.player = option::some<PlayerIcon>(PlayerIcon {
            player_id: vector::length<Player>(&room.players_list)
        });


    }

    /*
    Add input, to be simulated next turn
    */
    fun add_player_input(player: address, room_id: u64, x: u64, y: u64) acquires RoomsList {
        // assert!( (x >= 0 && x < C_SIZE) && (y >= 0 && y < C_SIZE), E_INVALID_INPUT);

        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

        // Check the player already exists
        // assert!(table::contains(&room.moves, player), E_PLAYER_ALREADY_JOINED);

        table::upsert(
            &mut room.moves,
            player,
            Move {
                x,
                y,
            }
        );

    }


    /*
    Use APTOS ROLL and simulate every move.
    Do it last.
    */
    public entry fun update_room(room_id: u64) acquires RoomsList {
        let players_len = {
            let rooms = borrow_global<RoomsList>(@revanth);
            let room = vector::borrow(&rooms.rooms_list, room_id);

            vector::length<Player>(&room.players_list)
        };

        let items_len = {
            let rooms = borrow_global<RoomsList>(@revanth);
            let room = vector::borrow(&rooms.rooms_list, room_id);

            vector::length<Item>(&room.items_list)
        };

        // Stage 1: Move Player
        let map = smart_table::new<Move, vector<u64>>();
        let moves = vector::empty<Move>();
        let map_ref = &mut map;


        let i = 0;
        while(i < players_len) {
            
            let (nextmove, room_id, current_pos) = {

                let rooms = borrow_global<RoomsList>(@revanth);
                let room = vector::borrow(&rooms.rooms_list, room_id);

                let player = vector::borrow(&room.players_list, i);
                let nextmove = table::borrow(&room.moves, player.address);

                (nextmove, room.id, player.position)
            };


            // Map Move->PLayerId
            if( smart_table::contains(map_ref, *nextmove) ) {
                let ids_list = smart_table::borrow_mut(map_ref, *nextmove);
                vector::push_back(
                    ids_list,
                    i,
                );
            }
            else {
                // new move map
                vector::push_back(
                    &mut moves,
                    *nextmove,
                );

                // add this move to table
                smart_table::add(
                    map_ref ,
                    *nextmove,
                    vector::singleton<u64>(i),
                );
            };
           

            i = i + 1;
        };

        // Iterate through Colliding moves, and move only one player
        let j = 0;
        while( j < vector::length(&moves)) {
            let nextmove = vector::borrow(&moves, j);
            let mapped_players = smart_table::borrow(map_ref, *nextmove);

            // ROLL to pick a player out MAX. 4
            let pick_id = get_rand_range(0, vector::length<u64>(mapped_players));

            let current_pos = {
                let rooms = borrow_global<RoomsList>(@revanth);
                let room = vector::borrow(&rooms.rooms_list, room_id);

                let player = vector::borrow(&room.players_list, i);
                player.position
            };

            // del old slot
            slot_del_player(room_id, current_pos.x, current_pos.y);

            // add new slot
            slot_add_player(room_id, pick_id, nextmove.x, nextmove.y);

            j = j + 1;
        };

        // drop the smart table
        smart_table::destroy(map);

        // Stage 2: Player + Item = Event ( Roll )
        i = 0;
        while(i < items_len) {
            let (item_code, position) = {
                let rooms = borrow_global<RoomsList>(@revanth);
                let room = vector::borrow(&rooms.rooms_list, room_id);

                let item = vector::borrow(&room.items_list, i);
                ( item.item_code, item.position )
            };

            // EVENT: BOX   
            if( item_code == I_BOX ) {
                // key probability

                // select a player to give key


                    // add to inventory

                    // Delete Item ( only from items_list )




            }
            // EVENT: EXIT DOOR
            else if( item_code == I_EXIT ) {
                // player should have key, only one player wins 


                // filter players with keys


                // pick a winner


                // give player WIN item


                // END flag

            }
            else {
                // pass
            };

        };

    }

    /*
    Adds item to the given room at x, y
    No collision check
    */
    fun add_item(roomid: u64, item_code: u8, x: u64, y: u64) acquires RoomsList{
        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, roomid);
        let items_len = vector::length<Item>(&room.items_list);

        // add to rooms item list
        vector::push_back(
            &mut room.items_list,
            Item {
                item_code,
                position: Move {
                    x,
                    y,
                },
                id: items_len,
            }
        );
        
    }

    /*
    Helper Functions
    */
    public fun get_slot_mut(grid: &mut vector<vector<Slot>>, x: u64, y: u64): &mut Slot  {
        let row = vector::borrow_mut(grid, y);

        vector::borrow_mut(row, x)
    }

    public fun get_slot(grid: &vector<vector<Slot>>, x: u64, y: u64): &Slot {
        let row = vector::borrow(grid, y);

        vector::borrow(row, x)
    }

    public fun get_rand_range(l: u64, _h: u64): u64 {

        l
    }

    /*
    Game Functions
    */
    fun slot_add_player(room_id: u64, player_id: u64, x: u64, y: u64) acquires RoomsList{
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut roomslist.rooms_list, room_id);

        let row = vector::borrow_mut(&mut room.grid, y);
        let slot = vector::borrow_mut(row, x);

        slot.player = option::some<PlayerIcon>(
            PlayerIcon {
                player_id,
            }
        );

        // also update player position ( not for items, cause items dont move, only appear / dissappear )
        let player = vector::borrow_mut(&mut room.players_list, player_id);
        player.position = Move {
            x,
            y,
        };

    }

    fun slot_del_player(room_id: u64, x: u64, y: u64) acquires RoomsList {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut roomslist.rooms_list, room_id);

        let row = vector::borrow_mut(&mut room.grid, y);
        let slot = vector::borrow_mut(row, x);

        slot.player = option::none<PlayerIcon>();
    }

    fun room_add_item(room_id: u64, item_code: u8, x: u64, y: u64) acquires RoomsList {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut roomslist.rooms_list, room_id);
        let len = vector::length<Item>(&room.items_list);

        vector::push_back(
            &mut room.items_list,
            Item {
                item_code,
                position: Move {x,y},
                id: len,
            }
        );

    }

    fun room_del_item(room_id: u64, item_id: u64) acquires RoomsList {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut roomslist.rooms_list, room_id);
        let len = vector::length<Item>(&room.items_list);

        {
            vector::swap_remove(
                &mut room.items_list,
                item_id,
            );
        };
        
        // AA for list, items cannot loose their context id
        let x_item = vector::borrow_mut(&mut room.items_list, item_id);
        x_item.id = item_id;
    }

    /*
    To Player's inventory
    */
    fun player_add_item(room_id: u64, player_id: u64, item_code: u8) acquires RoomsList {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut roomslist.rooms_list, room_id);
        let player = vector::borrow_mut(&mut room.players_list, player_id);

        table::upsert(
            &mut player.inventory,
            item_code,
            1,
        );

    }


    /*
    View Functions
    

    #[view]
    public entry fun get_rooms() : (vector<string::string>, vector<u64>, vector<u64>, u64) {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let names = vector::empty<string::string>();
        let ids = vector::empty<u64>();
        let counts = vector::empty<u64>();

        let i = 0;
        while(i < vector::length(&roomslist)) {
            let room = vector::borrow(&roomslist, i);

            vector::push_back(&names, room.name );
            vector::Push_back(&ids, i);
            vector::push_back(
                &counts,
                vector::length(&room.moves)
            );

            i = i + 1;
        };

        (names, ids, counts, C_MAX_PLAYERS)
    }

    
    /// Return the entire grid as a linear vector. returns Size for unpacking
    
    #[view]
    public entry fun get_one_room(room_id: u8): (vector<u64>, u64) {
        let series = vector::empty<u64>();

        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow(&roomslist.rooms_list, room_id);

        let i = 0;
        let j = 0;

        while(i < C_SIZE) {
            let row = vector::borrow(&room.grid, i);
            j = 0;
            while(j < C_SIZE) {
                let x = vector::borrow(&row, j);
                series.push_back(&mut series, x);

                j = j+1;
            };

            i = i+1;
        };

        (series, C_SIZE)
    }

    */

    #[test]
    fun test() {
        let ans = string::utf8(b"hello dapp!");
        debug::print(&ans);
    }

}