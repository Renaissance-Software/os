pub fn range(comptime n: u64) [n]comptime_int
{
    var dummy_arr = [_]comptime_int{0} ** n;
    for (dummy_arr) |*v, i|
    {
        v.* = i;
    }
    return dummy_arr;
}
