#!/usr/bin/perl

use Test::More;
use Test::Deep;

use qbit;

use lib::abs qw(../lib);

use QBit::QueryData;

my $data = [
    {id => 1, label => 'label 1', num => 1, val => 5,},
    {id => 2, label => 'label 2', num => 1, val => 6,},
    {id => 3, label => 'label 3', num => 2, val => undef,},
];

my $q = QBit::QueryData->new(data => $data);

try {
    $q->fields({caption => {CONCAT => {}}});
}
catch {
    is(shift->message, gettext('You must set arguments for function "%s": {%s => [...]}', 'CONCAT', 'CONCAT'));
}
finally {
    is(ref(shift), 'Exception');
};

$q->fields({caption => {CONCAT => ['label', \': ', 'num']}});

cmp_deeply($q->get_all(), [{caption => 'label 1: 1'}, {caption => 'label 2: 1'}, {caption => 'label 3: 2'}], 'CONCAT');

$q->fields({cnt => {COUNT => [\'*']}});

cmp_deeply($q->get_all(), [{cnt => 3}], 'COUNT(*)');

$q->fields({num => '', cnt => {COUNT => [\'*']}});
$q->group_by('num');

cmp_deeply($q->get_all(), [{num => 1, cnt => 2}, {num => 2, cnt => 1}], 'COUNT(*) with group by num');

$q->fields({num => '', cnt => {COUNT => ['val']}});

cmp_deeply($q->get_all(), [{num => 1, cnt => 2}, {num => 2, cnt => 0}], 'COUNT(val) with group by num');

$q->fields({num => '', cnt_id => {COUNT => ['id']}, cnt_val => {COUNT => ['val']}});

cmp_deeply(
    $q->get_all(),
    [{num => 1, cnt_val => 2, cnt_id => 2}, {num => 2, cnt_id => 1, cnt_val => 0}],
    'COUNT(val) and COUNT(id) with group by num'
);

$q->fields({sum => {SUM => ['val']}});
$q->group_by();

cmp_deeply($q->get_all(), [{sum => 11}], 'SUM(val)');

$q->fields({sum_val => {SUM => ['val']}, sum_num => {SUM => ['num']}});

cmp_deeply($q->get_all(), [{sum_val => 11, sum_num => 4}], 'SUM(val) and SUM(num)');

$q->fields({num => '', sum_val => {SUM => ['val']}, sum_id => {SUM => ['id']}});
$q->group_by('num');

cmp_deeply(
    $q->get_all(),
    [{num => 1, sum_val => 11, sum_id => 3}, {num => 2, sum_id => 3, sum_val => 0}],
    'SUM(val) and SUM(id) and group by num'
);

done_testing();
