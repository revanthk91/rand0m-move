module revanth::dapp {
    use std::debug;
    use std::string;
    use std::vector;
    use std::option;
    use std::signer;

    use aptos_framework::table;
    use aptos_framework::math64;
    use aptos_framework::smart_table;
    use aptos_framework::randomness;

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
        active: bool,
    }

    // Player (oomp)
    struct Player has key, store {
        address: address,
        inventory: table::Table<u8, u8>,
        position: Move,
    }

    // Item (oomp)
    struct Item has key, store, copy, drop {
        item_code: u8,
        position: Move,
        id: u64,
    }

    // Player ( lowest )
    struct Slot has key, store {
        player: option::Option<PlayerIcon>,
        used: bool,
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

    // VIEW returns
    struct RoomMiniView has key, store, drop, copy {
        name: string::String,
        id: u64,
        active: bool,
        player_count: u64,
        max_player_count: u64,
    }

    struct PlayerMiniView has key, store, drop, copy {
        address: address,
        inventory: vector<u64>,
        position: Move,
    }

    struct RoomsListView has key, store, drop, copy {
        rooms_list: vector<RoomMiniView>,
    }
    
    struct RoomView has key, store, drop, copy {
        name: string::String,
        id: u64,
        active: bool,
        players_list: vector<PlayerMiniView>,
        items_list: vector<Item>,
    }


    // items
    const I_EXIT: u8 = 0;
    const I_KEY: u8 = 1;
    const I_EMPTY_BOX: u8 = 2;
    const I_LOOT_BOX: u8 = 3;
    const I_WON: u8 = 4;

    // frequency distribution of items
    const I_COUNT: vector<u64> = vector[1, 0, 4, 1, 0];


    // directions
    const D_UP: u8 = 1;
    const D_RIGHT: u8 = 2;
    const D_DOWN: u8 = 3;
    const D_LEFT: u8 = 4;

    // size
    const C_SIZE: u64 = 15;
    const C_MAX_PLAYERS: u64 = 5;
    
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
    public entry fun create_room() acquires RoomsList {
        let room_id = {
            let roomslist = borrow_global_mut<RoomsList>(@revanth);
            let room_id = vector::length<Room>(&roomslist.rooms_list);
            let room = Room {
                name: string::utf8(b"New Room"),
                grid: vector::empty<vector<Slot>>(),
                id: room_id,
                moves: table::new<address, Move>(),
                active: true,
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
                            used: false,
                        }
                    );

                    j = j+1;
                };

                vector::push_back(&mut room.grid, row);
                i = i+1;
            };

            // finally add to RoomsList
            vector::push_back(&mut roomslist.rooms_list, room);

            room_id
        };

        // Construct Items
        let i = 0;
        let items = vector::empty<u64>();

        while(i < vector::length(&I_COUNT)) {
            let count = (*vector::borrow(&I_COUNT, i) as u64);
            let j = 0;
            while(j < count) {
                vector::push_back(&mut items, i);
                j = j + 1;
            };

            i = i + 1;
        };

        // Randomly Place items
        let n = math64::sqrt(vector::length(&items)) + 1;
        // C_ZONE_SIZE = 5, for now
        let s = C_SIZE / n;

        i = 0;
        while(i < n) {
            let j = 0;
            while(j < n) {
                // pick ONE point
                let x = get_rand_range(0, s);
                let y = get_rand_range(0, s);

                x = (i * s) + x;
                y = (j * s) + y;

                // get random item code, IF there are any
                if( vector::length(&items) > 0) {
                    let rid = get_rand_range(0, vector::length(&items));
                    let item_code = vector::remove(&mut items, rid);

                    // place item
                    // u64 -> u8, dangeorus
                    room_add_item(room_id, (item_code as u8), x, y);
                };

                j = j + 1;
            };

            i = i + 1;
        };

    }

    /*
    Adds player into the Room Moves Dictionary.
    */
    public entry fun add_player(player_addr: address, room_id: u64) acquires RoomsList {
        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);
        
        // random placement of player
        let player_id = vector::length(&room.players_list);
        let n = 3;

        let cx = player_id / n;
        let cy = player_id % n;

        let x = get_rand_range(0, 5);
        let y = get_rand_range(0, 5);
        
        x = (cx * 5) + x;
        y = (cy * 5) + y;

        let player = Player {
            address: player_addr,
            inventory: table::new<u8, u8>(),
            position: Move {
                x,
                y,
            }
        };

        // add in player list
        vector::push_back(
            &mut room.players_list,
            player,
        );

        // add in PlayerIcon to grid
        let slot = get_slot_mut(&mut room.grid, x, y);
        slot.player = option::some<PlayerIcon>(PlayerIcon {
            player_id: vector::length<Player>(&room.players_list) - 1,
        });

        // add input entry in moves
        table::upsert(
            &mut room.moves,
            player_addr,
            Move {
                x,y
            }
        );

    }

    /*
    Add input, to be simulated next turn
    */
    public entry fun add_player_input(player: address, room_id: u64, x: u64, y: u64) acquires RoomsList {
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

                let player = vector::borrow(&room.players_list, pick_id);
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
        // items to delete
        let items_to_delete = vector::empty<u64>();
        let items_del_mut_ref = &mut items_to_delete;
        let flag_win = false;

        i = 0;
        while(i < items_len) {
            let (item_code, position) = {
                let rooms = borrow_global<RoomsList>(@revanth);
                let room = vector::borrow(&rooms.rooms_list, room_id);

                let item = vector::borrow(&room.items_list, i);
                ( item.item_code, item.position )
            };

            // EVENT: LOOT BOX   
            if( item_code == I_LOOT_BOX ) {
                // key probability
                let has_key = get_rand_range(0,100) < 20;

                if(has_key) {
                    let rooms = borrow_global<RoomsList>(@revanth);
                    let room = vector::borrow(&rooms.rooms_list, room_id);
                    let slot = get_slot(&room.grid, position.x, position.y);
                        
                    if( option::is_some(&slot.player) ) {
                        // add to inventory
                        let p_icon = option::borrow<PlayerIcon>(&slot.player);
                        player_add_item(room_id, p_icon.player_id, I_KEY);


                        // delete box
                        vector::push_back(
                            items_del_mut_ref,
                            i,
                        );

                    }
                };
            }
            // EVENT: EXIT DOOR
            else if( item_code == I_EXIT ) {
                // player should have key
                let (p_id, has_key, slot_filled) = {
                    let rooms = borrow_global_mut<RoomsList>(@revanth);
                    let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);
                    let slot = get_slot(&room.grid, position.x, position.y);
                    let p_id;
                    let is;
                    let has_key;

                    if (option::is_some(&slot.player)) {
                        let p_icon = option::borrow<PlayerIcon>(&slot.player);
                        p_id = p_icon.player_id;
                        let p = vector::borrow(&room.players_list, p_id);
                        has_key = table::contains(&p.inventory, I_KEY);
                        is = true;
                    } 
                    else {
                        p_id = 0;
                        is = false;
                        has_key = false;
                    };

                    (p_id, has_key, is)
                };
 
                if( slot_filled && has_key ) {
                    // add win item
                    player_add_item(room_id, p_id, I_WON);

                    // end game
                    flag_win = true;
                };

            }
            else {
                // pass
            };

            i = i + 1;
        };

        // Step 3: Delete items now
        i = 0;
        while(i < vector::length(items_del_mut_ref)) {
            let id = vector::borrow(items_del_mut_ref, i);

            room_del_item(room_id, *id);

            i = i + 1;
        };   

        // Step 4: Process Flags ( because barrow checker is hell )
        if( flag_win ) {
            let rooms = borrow_global_mut<RoomsList>(@revanth);
            let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);
            room.active = false;
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
        // randomness::u64_range(l, _h)
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
        if( vector::length<Item>(&room.items_list) > 0) {
            let x_item = vector::borrow_mut(&mut room.items_list, item_id);
            x_item.id = item_id;
        }
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
    */
    #[view]
    public fun get_rooms(): vector<RoomMiniView> acquires RoomsList {
        let rooms = borrow_global<RoomsList>(@revanth);
        let i = 0;
        let vec = vector::empty<RoomMiniView>();

        let rooms_ref = &rooms.rooms_list;
        while( i < vector::length(rooms_ref)) {
            let room = vector::borrow(rooms_ref, i);
            vector::push_back(
                &mut vec,
                RoomMiniView {
                    id: room.id,
                    name: room.name,
                    active: room.active,
                    player_count: vector::length(&room.players_list),
                    max_player_count: C_MAX_PLAYERS,
                }
            );

            i = i + 1;
        };

        vec
    } 

    #[view]
    public fun get_room(room_id: u64): RoomView acquires RoomsList {
        let rooms = borrow_global<RoomsList>(@revanth);
        let room = vector::borrow<Room>(&rooms.rooms_list, room_id);

        let vec = vector::empty<PlayerMiniView>();

        let i = 0;
        while(i < vector::length(&room.players_list)) {
            let j : u8 = 0;
            let p = vector::borrow(&room.players_list, i);
            let vec2 = vector::empty<u64>();

            while((j as u64) <= vector::length(&I_COUNT)) {
                if( table::contains(&p.inventory, j)) {
                    vector::push_back(&mut vec2, (j as u64) );
                };

                j = j + 1;
            };

            debug::print(&vec2);

            vector::push_back(
                &mut vec,
                PlayerMiniView {
                    address: p.address,
                    inventory: vec2,
                    position: p.position,
                }
            );

            i = i + 1;
        };

        let room_view = RoomView {
            name: room.name,
            id: room.id,
            active: room.active,
            players_list: vec,
            items_list: room.items_list,
        };

        room_view
    }   


    #[test(admin=@revanth, fx=@aptos_framework)]
    fun movement_test(admin: &signer, fx: &signer) acquires RoomsList {
        // init OK
        init_module(admin);

        // create a room OK
        create_room();

        // players
        add_player(signer::address_of(admin), 0);
        add_player(signer::address_of(fx), 0);

        print_room(0);
    }

    #[test_only]
    fun print_room(id: u64) acquires RoomsList {
        let rooms = borrow_global<RoomsList>(@revanth);
        let room = vector::borrow(&rooms.rooms_list, id);

        

        debug::print(room);
    }

}