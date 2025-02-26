use array::ArrayTrait;
use integer::U32DivRem;
use option::OptionTrait;
use poseidon::poseidon_hash_span;
use starknet::{storage_read_syscall, storage_write_syscall, SyscallResult, SyscallResultTrait};
use starknet::storage_access::{
    Store, StorageBaseAddress, storage_address_to_felt252, storage_address_from_base,
    storage_address_from_base_and_offset, storage_base_address_from_felt252
};
use traits::{Default, DivRem, IndexView, Into, TryInto};

const POW2_8: u32 = 256; // 2^8

#[derive(Drop)]
struct List<T> {
    address_domain: u32,
    base: StorageBaseAddress,
    len: u32, // number of elements in array
    storage_size: u8
}

trait ListTrait<T> {
    fn len(self: @List<T>) -> u32;
    fn is_empty(self: @List<T>) -> bool;
    fn append(ref self: List<T>, value: T) -> u32;
    fn get(self: @List<T>, index: u32) -> Option<T>;
    fn set(ref self: List<T>, index: u32, value: T);
    fn clean(ref self: List<T>);
    fn pop_front(ref self: List<T>) -> Option<T>;
    fn array(self: @List<T>) -> Array<T>;
    fn from_array(ref self: List<T>, array: @Array<T>);
    fn from_span(ref self: List<T>, span: Span<T>);
}

impl ListImpl<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>, impl TStore: Store<T>> of ListTrait<T> {
    fn len(self: @List<T>) -> u32 {
        *self.len
    }

    fn is_empty(self: @List<T>) -> bool {
        *self.len == 0
    }

    fn append(ref self: List<T>, value: T) -> u32 {
        let (base, offset) = calculate_base_and_offset_for_index(
            self.base, self.len, self.storage_size
        );
        Store::write_at_offset(self.address_domain, base, offset, value).unwrap_syscall();

        let append_at = self.len;
        self.len += 1;
        Store::write(self.address_domain, self.base, self.len);

        append_at
    }

    fn get(self: @List<T>, index: u32) -> Option<T> {
        if (index >= *self.len) {
            return Option::None;
        }

        let (base, offset) = calculate_base_and_offset_for_index(
            *self.base, index, *self.storage_size
        );
        let t = Store::read_at_offset(*self.address_domain, base, offset).unwrap_syscall();
        Option::Some(t)
    }

    fn set(ref self: List<T>, index: u32, value: T) {
        assert(index < self.len, 'List index out of bounds');
        let (base, offset) = calculate_base_and_offset_for_index(
            self.base, index, self.storage_size
        );
        Store::write_at_offset(self.address_domain, base, offset, value).unwrap_syscall();
    }

    fn clean(ref self: List<T>) {
        self.len = 0;
        Store::write(self.address_domain, self.base, self.len);
    }

    fn pop_front(ref self: List<T>) -> Option<T> {
        if self.len == 0 {
            return Option::None;
        }

        let popped = self.get(self.len - 1);
        // not clearing the popped value to save a storage write,
        // only decrementing the len - makes it unaccessible through
        // the interfaces, next append will overwrite the values
        self.len -= 1;
        Store::write(self.address_domain, self.base, self.len);

        popped
    }

    fn array(self: @List<T>) -> Array<T> {
        let mut array = array![];
        let mut index = 0;
        loop {
            if index == *self.len {
                break;
            }
            array.append(self.get(index).expect('List index out of bounds'));
            index += 1;
        };
        array
    }

    fn from_array(ref self: List<T>, array: @Array<T>) {
        self.from_span(array.span());
    }

    fn from_span(ref self: List<T>, mut span: Span<T>) {
        let mut index = 0;
        self.len = span.len();
        loop {
            match span.pop_front() {
                Option::Some(v) => {
                    let (base, offset) = calculate_base_and_offset_for_index(
                        self.base, index, self.storage_size
                    );
                    Store::write_at_offset(self.address_domain, base, offset, *v).unwrap_syscall();
                    index += 1;
                },
                Option::None => { break; }
            };
        };
        Store::write(self.address_domain, self.base, self.len);
    }
}

impl AListIndexViewImpl<
    T, impl TCopy: Copy<T>, impl TDrop: Drop<T>, impl TStore: Store<T>
> of IndexView<List<T>, u32, T> {
    fn index(self: @List<T>, index: u32) -> T {
        self.get(index).expect('List index out of bounds')
    }
}

// this functions finds the StorageBaseAddress of a "storage segment" (a continuous space of 256 storage slots)
// and an offset into that segment where a value at `index` is stored
// each segment can hold up to `256 // storage_size` elements
//
// the way how the address is calculated is very similar to how a LegacyHash map works:
//
// first we take the `list_base` address which is derived from the name of the storage variable
// then we hash it with a `key` which is the number of the segment where the element at `index` belongs (from 0 upwards)
// we hash these two values: H(list_base, key) to the the `segment_base` address
// finally, we calculate the offset into this segment, taking into account the size of the elements held in the array
//
// by way of example:
//
// say we have an List<Foo> and Foo's storage_size is 8
// struct storage: {
//    bar: List<Foo>
// }
//
// the storage layout would look like this:
//
// segment0: [0..31] - elements at indexes 0 to 31
// segment1: [32..63] - elements at indexes 32 to 63
// segment2: [64..95] - elements at indexes 64 to 95
// etc.
//
// where addresses of each segment are:
//
// segment0 = hash(bar.address(), 0)
// segment1 = hash(bar.address(), 1)
// segment2 = hash(bar.address(), 2)
//
// so for getting a Foo at index 90 this function would return address of segment2 and offset of 26

fn calculate_base_and_offset_for_index(
    list_base: StorageBaseAddress, index: u32, storage_size: u8
) -> (StorageBaseAddress, u8) {
    let max_elements = POW2_8 / storage_size.into();
    let (key, offset) = U32DivRem::div_rem(index, max_elements.try_into().unwrap());

    // hash the base address and the key which is the segment number
    let addr_elements = array![
        storage_address_to_felt252(storage_address_from_base(list_base)), key.into()
    ];
    let segment_base = storage_base_address_from_felt252(poseidon_hash_span(addr_elements.span()));

    (segment_base, offset.try_into().unwrap() * storage_size)
}

impl ListStore<T, impl TStore: Store<T>> of Store<List<T>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<List<T>> {
        let len: u32 = Store::read(address_domain, base).unwrap_syscall();
        let storage_size: u8 = Store::<T>::size();
        Result::Ok(List { address_domain, base, len, storage_size })
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: List<T>) -> SyscallResult<()> {
        Store::write(address_domain, base, value.len)
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<List<T>> {
        let len: u32 = Store::read_at_offset(address_domain, base, offset).unwrap_syscall();
        let storage_size: u8 = Store::<T>::size();
        Result::Ok(List { address_domain, base, len, storage_size })
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: List<T>
    ) -> SyscallResult<()> {
        Store::write_at_offset(address_domain, base, offset, value.len)
    }

    fn size() -> u8 {
        Store::<u8>::size()
    }
}
