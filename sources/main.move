module revanth::dapp {
    use std::debug;
    use std::string;
    use std::vector;
    use std::option;

    use aptos_framework::table;
    use aptos_framework::randomness;


    // error codes
    E_INVALID_INPUT = 1;


    // Table of Room
    struct RoomsList has key {
        rooms_list: vector<Room>,
    }

    // Room
    struct Room has key {
        name: string::string,
        grid: vector<vector<Slot>>,
        id: u64,
        moves: table::Table<address,Move>,
        players_list: vector<Player>,
        items_list: vector<Item>,
        inactive: bool,
    }

    // Player (oomp)
    struct Player has key {
        address: address,
        inventory: vector<u64>,
        i: u64,
        j: u64,
    }

    // Item (oomp)
    struct Item has key {
        item_code: u64,
        i: u64,
        j: u64,
    }

    // Player ( lowest )
    struct Slot has key {
        players_list: vector<&Player>,
        item: option<&Item>,
    }

    // Move ( really )
    struct Move has key {
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
    fun init_module() {
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
    fun create_room() {
        let roomslist = borrow_global_mut<RoomsList>(@revanth);
        let grid = vector::empty<vector<u64>>();

        let i = 0;
        let j = 0;

        while(i < C_SIZE) {
            let row = vector::empty<u64>();

            j = 0;
            while(j < C_SIZE) {
                row.push_back(0);
                j = j+1;
            };

            room.push_back(row);
            i = i+1;
        };

        let room = Room {
            name: string::utf8(b"New Room"),
            grid,
            id: vector::length(roomslist.rooms_list),
            moves: table::empty<address, u8>(),
        };

        vector::push_back(&mut roomslist.room_list, room);
    }

    /*
    Adds player into the Room Moves Dictionary.
    */
    fun add_player(player: address, room_id: u8) {
        // mint? idc
        let rooms = borrow_global_mut<RoomsList>(@revanth);

        // Verify Payment, Get payment, Mint coin, IDK

        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);
        table::add(&mut room.moves, address, 0);
    }

    /*
    Add input, to be simulated next turn
    */
    fun add_player_input(player: address, room_id: u8, x: u64, y: u64) {
        assert!(x >= 0 && x < C_SIZE && y >= 0 && y < C_SIZE, E_INVALID_INPUT);

        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);

        // Check the player already exists
        assert!(table::contains(&room.moves, player));

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
    public entry fun update_room(room_id: u64) {
        let rooms = borrow_global_mut<RoomsList>(@revanth);
        let room = vector::borrow_mut(&mut rooms.rooms_list, room_id);
        let i;
        let deleted_items = vector::empty<u64>();
        let added_items = vector::empty<u64>();

        /// Stage 1: Move Player
        i = 0;
        while(i < vector::length(&room.players_list)) {
            // one step move
            let player = vector::borrow(&room.players_list, i);
            let newmove = table::borrow(&room.moves, player.address);

            let newslot = get_slot(&room.grid, newmove.x, newmove.y);
            let slot = get_slot(&room.grid, player.x, player.y);

            // move to new slot
            vector::push_back(
                &newslot.players_list,
                player,
            );

            // delete player from old slot ( illusion of movement )
            let j = 0;
            while(j < vector::length(&slot.players_list)) {
                
                if(p == player) {
                    vector::remove(
                        &mut slot.players_list,
                        j
                    );
                    break;
                };

                j =  j+ 1;
            };
        };

        /// Stage 2: Player + Item fusion ( Roll )
        i = 0;
        while(i < vector::length(&room.items_list)) {
            let item = vector::borrow(&room.items_list, i);
            let slot = vector::borrow(
                vector::borrow(room.grid, i),
                item.j,
            );
            let slot_players = slot.players;
            

            // EVENT: BOX
            if( item.item_code == I_BOX ) {
                // box may have key
                // key reaches one player
                let has_key = randomness:u64_range(0,100) < 50;
                let select_player = vector::borrow(
                    &slot_players,
                    randomness::u64_range(0, vector::length(&slot_players))
                );

                if(has_key) {
                    vector::push_back(
                        select_player.inventory,
                        I_KEY,
                    );

                    // Delete Item ( only from items_list )
                    deleted_items.push_back(i);
                };

            }
            // EVENT: EXIT DOOR
            else if( item.item_code == I_EXIT ) {
                // player should have key, only one player wins
                // key opens door
                let j = 0;
                let players_w_keys = vector::empty<&Player>
                let player_won = vector::borrow(
                    &players_w_keys,
                    randomness::u64_range(0, vector::length(&players_w_keys))
                );

                // give player WIN item
                vector::push_back(
                    &mut player_won.inventory,
                    I_WON,
                );

                // END flag
                room.inactive = true;
            }
            else {
                // pass
            };

        };

        /// Stage 3: Appear or Dissappear Items ( memmory reallocation )
        // Delete Items
        i = 0;
        while(i < vector::length(&deleted_items)) {
            vector::remove(
                &mut room.items_list,
                vector::borrow(&deleted_items, i),
            );
        };

    }

    /*
    Helper Functions
    */
    public fun get_slot(i: u64, j: u64, grid: &vector<vector<Slot>>): &Slot {
        let row = vector::borrow(grid, j);

        vector::borrow(row, i);
    }

    /*
    View Functions
    */
    #[view]
    public entry fun get_rooms() : (vector<string::string>, vector<u64>, vector<u64>, u64)
    {
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

    /*
    Return the entire grid as a linear vector. returns Size for unpacking
    */
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


    #[test]
    fun test() {
        let ans = string::utf8(b"hello dapp!");
        debug::print(&ans);
    }

}