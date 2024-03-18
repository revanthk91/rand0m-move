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
    const E_INVALID_INPUT: u64 = 1;
    const E_PLAYER_ALREADY_JOINED: u64 = 2;
    const E_INVALID_CRAFT: u64 = 3;

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
        crafts: table::Table<u64, option::Option<vector<u64>>>,
        players_list: vector<Player>,
        items_list: vector<Item>,
        active: bool,
        winner: option::Option<address>,
        max_player_count: u64,
    }

    // Player (oomp)
    struct Player has key, store {
        address: address,
        inventory: table::Table<u64, u64>,
        position: Move,
        id: u64,
    }

    // Item (oomp)
    struct Item has key, store, copy, drop {
        item_code: u64,
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


    // GameState
    struct GameState has key, store {
        crafts: table::Table<vector<u64>, vector<u64>>,
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
        id: u64,
    }

    struct RoomsListView has key, store, drop, copy {
        rooms_list: vector<RoomMiniView>,
    }
    
    struct RoomView has key, store, drop, copy {
        name: string::String,
        id: u64,
        active: bool,
        winner: option::Option<address>,
        players_list: vector<PlayerMiniView>,
        items_list: vector<Item>,
    }


    // thats it
    const C_MAX_ITEM: u64 = 5; // 1 2 3 4 5 999

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

        move_to<GameState>(
            account,
            GameState {
                crafts: table::new<vector<u64>, vector<u64>>(),
            }
        );
    }

    /*
    Creates a single room and adds it to RoomList
    */
    entry fun create_room() acquires RoomsList {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let room_id = vector::length<Room>(&roomslist.rooms_list);
        let room = Room {
            name: string::utf8(b"New Room"),
            grid: vector::empty<vector<Slot>>(),
            id: room_id,
            moves: table::new<address, Move>(),
            crafts: table::new<u64, option::Option<vector<u64>>>(),
            active: false,
            players_list: vector::empty<Player>(),
            items_list: vector::empty<Item>(),
            winner: option::none(),
            max_player_count: C_MAX_PLAYERS,
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
    }


    /*
    Adds player into the Room Moves Dictionary.
    */
    entry fun add_player(player_addr: address, room_id: u64) acquires RoomsList {
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
            inventory: table::new<u64, u64>(),
            position: Move {
                x,
                y,
            },
            id: player_id,
        };

        // initialize inventory
        let i = 0;
        while(i <= C_MAX_ITEM) {
            table::upsert(
                &mut player.inventory,
                i,
                0,
            );

            i = i + 1;
        };

        // also the CHAOS
        table::upsert(
            &mut player.inventory,
            999,
            0,
        );


        // add in player list
        vector::push_back(
            &mut room.players_list,
            player,
        );

        // add in PlayerIcon to grid
        let slot = get_slot_mut(&mut room.grid, x, y);
        slot.player = option::some<PlayerIcon>(PlayerIcon {
            player_id,
        });

        // add input entry in moves
        table::upsert(
            &mut room.moves,
            player_addr,
            Move {
                x,y
            }
        );

        // add input entry in crafts
        table::upsert(
            &mut room.crafts,
            player_id,
            option::none(),
        );

    }

    /*
    Add player craft
    */
    entry fun add_player_craft(room_id: u64, player_id: u64, a: u64, b: u64) acquires RoomsList {
        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

        // sort
        if(a > b) {
            let x = a;
            a = b;
            b = x;
        };

        table::upsert(
            &mut room.crafts,
            player_id,
            option::some(vector[a,b]),
        );

    }

    /*
    DEV ONLY
    Add new craft
    */
    entry fun add_craft(a: u64, b: u64, c: u64, p: u64) acquires GameState {
        let gamestate = borrow_global_mut<GameState>(@revanth);

        // so, order doesnt matter anymore
        if (a > b) {
            let x = a;
            a = b;
            b = x;
            // swap
        };
        
        // add / modify recipes. you asked, you got.
        table::upsert(
            &mut gamestate.crafts,
            vector[a,b],
            vector[c,p],
        );

    }

    /*
    Add input, to be simulated next turn
    */
    entry fun add_player_input(player: address, room_id: u64, x: u64, y: u64) acquires RoomsList {
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
    entry fun update_room(room_id: u64) acquires RoomsList, GameState {
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

        // Stage 0:
        {
            let rooms = borrow_global_mut<RoomsList>(@revanth);
            let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

            if(players_len < C_MAX_PLAYERS || option::is_some(&room.winner)) {
                room.active = false;
                return;
            }
            else {
                room.active = true;
            };

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
            let rid = get_rand_range(0, vector::length<u64>(mapped_players));
            let pick_id = *vector::borrow(mapped_players, rid);

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

        // Stage 2: Item goes to Player Inventory
        // items to delete
        let items_to_delete = vector::empty<u64>();
        let items_del_mut_ref = &mut items_to_delete;

        i = 0;
        while(i < items_len) {
            let rooms = borrow_global_mut<RoomsList>(@revanth);
            let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

            let item = vector::borrow(&room.items_list, i);
            let row = vector::borrow_mut(&mut room.grid, item.position.y);
            let slot = vector::borrow_mut(row, item.position.x);

            if( option::is_some(&slot.player) ) {
                // actual action
                let picon = option::borrow<PlayerIcon>(&slot.player);
                let player = vector::borrow_mut(&mut room.players_list, picon.player_id);
                let inventory = &mut player.inventory;

                // add item
                // 0TH
                if( !table::contains(inventory, item.item_code) ) {
                    table::upsert(
                        inventory,
                        item.item_code,
                        0
                    );
                };

                // upsert
                let x = *table::borrow(inventory, item.item_code);
                x = x + 1;
                
                table::upsert(
                    inventory,
                    item.item_code,
                    x,
                );

                // add to delete
                vector::push_back(
                    items_del_mut_ref,
                    item.id,
                );

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

        // Step 4: Craft
        {
            let rooms = borrow_global_mut<RoomsList>(@revanth);
            let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

            i = 0;
            while(i < vector::length(&room.players_list)) {
                let craft = table::borrow(&room.crafts, i);
                let player = vector::borrow_mut(&mut room.players_list, i);
                let inventory = &mut player.inventory;

                if(option::is_some(craft)) {
                    let ab = option::borrow<vector<u64>>(craft);
                    let a = *vector::borrow(ab, 0);
                    let b = *vector::borrow(ab, 1);
                    let c = 0;

                    // just -1, a,b
                    // consume first, gen later
                    let x = *table::borrow(inventory, a);
                    let y = *table::borrow(inventory, b);

                    if( x <= 0 || y <= 0 ) {
                        continue;
                    };

                    table::upsert(
                        inventory,
                        a,
                        x - 1,
                    ); 

                    table::upsert(
                        inventory,
                        b,
                        y - 1,
                    );

                    // CHAOS IS 0, SKY IS 999
                    if(a == 0 && b == 0) {
                        // * + *
                        c = roll_craft(999, 1);
                    }
                    else if(a == 0) {
                        // * + b
                        let x = get_rand_range(1, C_MAX_ITEM + 1);

                        c = roll_craft(x, 10);
                    }
                    else {
                        // a + b, the only GameState
                        let gamestate = borrow_global<GameState>(@revanth);

                        if( table::contains(&gamestate.crafts, vector[a,b])) {
                            let match = table::borrow(
                                &gamestate.crafts,
                                vector[a,b],
                            );

                            let c = *vector::borrow(match, 0);
                            let p = *vector::borrow(match, 1);

                            c = roll_craft(c, p);
                        };
                        
                    };

                    // finally add c
                    x = *table::borrow(inventory, c);
                    table::upsert(
                        inventory,
                        c,
                        x + 1,
                    );

                    // sky
                    if(c == 999) room.winner = option::some(player.address);

                };

                i = i + 1;
            };


        };

        // Step 4.1 Clear Craft Inputs
        {
            let i = 0;
            let rooms = borrow_global_mut<RoomsList>(@revanth);
            let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

            while(i < vector::length(&room.players_list)) {

                // upsert to option::none
                table::upsert(
                    &mut room.crafts,
                    i,
                    option::none(),
                );

                i = i + 1;
            };
        };

        // Step 5: Stream of Randomness
        {
            let rx = get_rand_range(0, 15);
            let ry = get_rand_range(0, 15);
            let rcode = get_rand_range(1, C_MAX_ITEM + 1);

            room_add_item(room_id, rcode, rx, ry);

        };


    }

    /*
    Roll Craft with probablity P
    */
    fun roll_craft(c: u64, p:u64): u64 {
        let r = get_rand_range(0,100);

        if(r < p) {
            return c;
        };

        0 // CHAOS
    }



    /*
    Adds item to the given room at x, y
    No collision check
    */
    fun add_item(roomid: u64, item_code: u64, x: u64, y: u64) acquires RoomsList{
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
    fun get_slot_mut(grid: &mut vector<vector<Slot>>, x: u64, y: u64): &mut Slot  {
        let row = vector::borrow_mut(grid, y);

        vector::borrow_mut(row, x)
    }

    fun get_slot(grid: &vector<vector<Slot>>, x: u64, y: u64): &Slot {
        let row = vector::borrow(grid, y);

        vector::borrow(row, x)
    }

    fun get_rand_range(l: u64, _h: u64): u64 {
        randomness::u64_range(l, _h)
        // l
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

    fun room_add_item(room_id: u64, item_code: u64, x: u64, y: u64) acquires RoomsList {
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
            let j = 0;
            let p = vector::borrow(&room.players_list, i);
            let vec2 = vector::empty<u64>();

            while(j <= C_MAX_ITEM) {
                let count = *table::borrow(&p.inventory, j);
                let k = 0;
                while(k < count) {
                    vector::push_back(
                        &mut vec2,
                        j,
                    );

                    k = k + 1;
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
                    id: i,
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
            winner: room.winner,
        };

        room_view
    }   


    #[test(admin=@revanth, fx=@0x25, fx2=@0x26)]
    fun movement_test(admin: &signer, fx: &signer, fx2: &signer) acquires RoomsList, GameState {
        // init OK
        init_module(admin);

        // create a room OK
        create_room();

        // players
        add_player(signer::address_of(admin), 0);
        add_player(signer::address_of(fx), 0);

        update_room(0);

        let v = get_room(0);
        debug::print(&v);

        update_room(0);
        v = get_room(0);
        debug::print(&v);

        update_room(0);
        v = get_room(0);
        debug::print(&v);

        add_player_input(signer::address_of(admin), 0, 1, 0);
        add_player_craft(0, 0, 1, 1);
        
        update_room(0);
        v = get_room(0);
        debug::print(&v);

    }

    #[test_only]
    fun print_room(id: u64) acquires RoomsList {
        let rooms = borrow_global<RoomsList>(@revanth);
        let room = vector::borrow(&rooms.rooms_list, id);


        debug::print(room);
    }

}