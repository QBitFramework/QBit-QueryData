package QBit::QueryData;

use qbit;

use base qw(QBit::Class);

__PACKAGE__->mk_accessors(qw(definition));

my $FILTER_OPERATIONS = {
    number => {
        '='      => '==',
        '!='     => '==',
        '<>'     => '==',
        '>'      => '>',
        '>='     => '>=',
        '<'      => '<',
        '<='     => '<=',
        'IN'     => '==',
        'NOT IN' => '==',
        'IS'     => '==',
        'IS NOT' => '==',
    },
    string => {
        '='        => 'eq',
        '!='       => 'eq',
        '<>'       => 'eq',
        '>'        => 'gt',
        '>='       => 'ge',
        '<'        => 'lt',
        '<='       => 'le',
        'IN'       => 'eq',
        'NOT IN'   => 'eq',
        'IS'       => 'eq',
        'IS NOT'   => 'eq',
        'LIKE'     => '=~',
        'NOT LIKE' => '=~',
    },
};

my $ORDER_OPERATIONS = {
    number => '<=>',
    string => 'cmp',
};

sub init {
    my ($self) = @_;

    $self->{'fields'} = {map {$_ => ''} @{$self->{'fields'}}} if ref($self->{'fields'}) eq 'ARRAY';

    $self->definition({}) unless defined($self->definition);

    $self->data($self->{'data'} // []);

    $self->fields($self->get_fields());

    $self->filter($self->{'filter'});
}

sub data {
    my ($self, $data) = @_;

    if (defined($data)) {
        delete($self->{'__ALL_FIELDS__'});

        foreach my $field (sort keys(%{$data->[0] // {}})) {
            $self->{'__ALL_FIELDS__'}{$field} = '';
        }

        unless (%{$self->{'__PROCESS_FIELDS__'} // {}}) {
            $self->fields($self->get_fields());
        }

        $self->{'data'} = $data;
    }

    return $self->{'data'};
}

sub fields {
    my ($self, $set_fields) = @_;

    if (defined($set_fields)) {
        $set_fields = {map {$_ => ''} @$set_fields} if ref($set_fields) eq 'ARRAY';

        unless (%$set_fields) {
            #default
            delete($self->{'__FIELDS__'});
        } else {
            #set fields
            $self->{'__FIELDS__'} = $set_fields;
        }
    } else {
        #all fields
        delete($self->{'__FIELDS__'});
        delete($self->{'fields'});
    }

    if (exists($self->{'__ALL_FIELDS__'})) {
        delete($self->{'__PROCESS_FIELDS__'});

        my $fields = $self->get_fields();

        foreach my $field (keys(%$fields)) {
            my $path = $self->_get_path($field);

            my $func_name;
            if (@$path > 1 || ref($fields->{$field}) eq '') {
                $func_name = 'FIELD';
            } elsif (ref($fields->{$field}) eq 'HASH') {
                $func_name = [%{$fields->{$field}}]->[0];
            } else {
                throw 'Unknown field';
            }

            my $class = $self->_get_process_class($func_name);

            $self->{'__PROCESS_FIELDS__'}{$field} =
              $class->new(name => $func_name, qd => $self, path => $path, fields => $fields, field => $field);
        }

        my $error_message =
          join("\n", map {$_->get_error_message} grep {$_->has_errors} values(%{$self->{'__PROCESS_FIELDS__'}}));

        throw Exception $error_message if $error_message;
    }

    return $self;
}

sub _get_process_class {
    my ($self, $name) = @_;

    my $class_prefix = 'QBit::QueryData::Function::';
    my $class        = $class_prefix . uc($name);

    my $file_path = "$class.pm";
    $file_path =~ s/::/\//g;

    unless (exists($INC{$file_path})) {
        require $file_path;
    }

    return $class;
}

sub get_fields {
    my ($self) = @_;

    return $self->{'__FIELDS__'} // $self->{'fields'} // $self->{'__ALL_FIELDS__'};
}

sub filter {
    my ($self, $filter) = @_;

    if (defined($filter)) {
        $self->{'__FILTER__'} = eval($self->_get_filter($filter));
    } else {
        delete($self->{'__FILTER__'});
    }

    return $self;
}

sub all_langs {
    my ($self, $value) = @_;

    $self->{'__ALL_LANGS__'} = $value // TRUE;

    return $self;
}

sub distinct {
    my ($self, $value) = @_;

    $self->{'__DISTINCT__'} = $value // TRUE;

    return $self;
}

sub insensitive {
    my ($self, $value) = @_;

    $self->{'__INSENSITIVE__'} = $value // TRUE;

    return $self;
}

sub for_update { }

sub order_by {
    my ($self, @order_by) = @_;

    unless (@order_by) {
        delete($self->{'__ORDER_BY__'});

        return $self;
    }

    @order_by = map {[ref($_) ? ($_->[0], $_->[1]) : ($_, 0)]} @order_by;

    $self->{'__ORDER_BY__'} = eval($self->_get_order(@order_by));

    return $self;
}

sub limit {
    my ($self, $offset, $limit) = @_;

    if (defined($limit)) {
        $self->{'__OFFSET__'} = $offset // 0;

        $self->{'__LIMIT__'} = $limit;
    } else {
        delete($self->{'__OFFSET__'});
        delete($self->{'__LIMIT__'});
    }

    return $self;
}

sub calc_rows {
    my ($self) = @_;

    $self->{'__CALC_ROWS__'} = TRUE;

    return $self;
}

sub found_rows {
    my ($self) = @_;

    return scalar(@{$self->data});
}

sub get_all {
    my ($self, %opts) = @_;

    my $fields      = $self->get_fields() // {};
    my @fields      = keys(%$fields);
    my @aggregators = ();

    foreach (@fields) {
        if ($self->{'__PROCESS_FIELDS__'}{$_}) {
            if ($self->{'__PROCESS_FIELDS__'}{$_}->can('init_storage')) {
                $self->{'__PROCESS_FIELDS__'}{$_}->init_storage();
            }

            if ($self->{'__PROCESS_FIELDS__'}{$_}->can('aggregation')) {
                push(@aggregators, $_);
            }

            #TODO: подумать над реализацией двух функций над одним полем
            #проверить что две группирующие функции не используются над одни полем
        }
    }

    my @group_by = @{$self->{'__PATHS_GROUP_BY__'} // []};

    my %uniq = ();
    my @data = ();
    foreach my $row (@{$self->{'data'}}) {
        next if defined($self->{'__FILTER__'}) && !$self->{'__FILTER__'}->($row);

        my $new_row = {};
        foreach my $field (@fields) {
            $new_row->{$field} = $self->{'__PROCESS_FIELDS__'}{$field}->process($row);
        }

        if (@group_by) {
            my $key =
              join($;, map {$self->get_field_value_by_path($row, $new_row, undef, @$_) // '__UNDEF__'} @group_by);

            if (exists($uniq{$key})) {
                # ключ совпадает, только агрегируем
                $data[$uniq{$key}]->{$_} = $self->{'__PROCESS_FIELDS__'}{$_}->aggregation($row, $key)
                  foreach @aggregators;
            } else {
                # строка с новым ключом
                push(@data, $new_row);

                $uniq{$key} = $#data;
            }
        } elsif (@aggregators) {
            # нет группировок но есть агригирующие функции
            unless (@data) {
                # результат одна строка
                push(@data, $new_row);
            }

            $data[0]->{$_} = $self->{'__PROCESS_FIELDS__'}{$_}->aggregation($row, $_) foreach @aggregators;
        } else {
            push(@data, $new_row);
        }
    }

    if ($self->_has_distinct && (!@group_by || !$self->_grouping_has_resulting_fields())) {
        %uniq = ();

        #TODO: inplace algorithm?
        my @tmp_data = ();
        foreach my $row (@data) {
            my $key = join($;, map {$row->{$_} // '__UNDEF__'} @fields);

            unless ($uniq{$key}) {
                $uniq{$key} = TRUE;

                push(@tmp_data, $row);
            }
        }

        @data = @tmp_data;
    }

    if (defined($self->{'__ORDER_BY__'})) {
        @data = sort {$self->{'__ORDER_BY__'}->($a, $b)} @data;
    }

    if (defined($self->{'__LIMIT__'})) {
        $self->{'__OFFSET__'} //= 0;

        return [] if $self->{'__OFFSET__'} >= @data;

        my $high = $self->{'__OFFSET__'} + $self->{'__LIMIT__'} - 1;

        $high = $#data if $high > $#data;

        @data = @data[$self->{'__OFFSET__'} .. $high];
    }

    return \@data;
}

sub _has_distinct {
    my ($self) = @_;

    return $self->{'__DISTINCT__'}
      || grep {ref($self->{'__PROCESS_FIELDS__'}{$_}) =~ /::DISTINCT\z/} keys(%{$self->{'__PROCESS_FIELDS__'}});
}

sub _grouping_has_resulting_fields {
    my ($self) = @_;

    my %group_by = map {$_ => TRUE} @{$self->{'__GROUP_BY__'} // []};

    foreach my $field (keys(%{$self->{'__PROCESS_FIELDS__'}})) {
        my $main_field = $self->{'__PROCESS_FIELDS__'}{$field}->get_main_field();
        return TRUE if $group_by{$main_field};
    }

    return FALSE;
}

sub group_by {
    my ($self, @group_by) = @_;

    unless (@group_by) {
        delete($self->{'__GROUP_BY__'});
        delete($self->{'__PATHS_GROUP_BY__'});

        return $self;
    }

    my @paths = map {$self->_get_path($_)} @group_by;

    my $fields = $self->get_fields() // {};
    if (exists($self->{'__ALL_FIELDS__'})) {
        my @unknown_fields = ();
        foreach my $path (@paths) {
            if (!exists($self->{'__ALL_FIELDS__'}{$path->[0]{'key'}}) && !exists($fields->{$path->[0]{'key'}})) {
                push(@unknown_fields, $path->[0]{'key'});
            }
        }

        throw Exception::BadArguments gettext("You can't grouping by following fields: %s", join(', ', @unknown_fields))
          if @unknown_fields;
    }

    my %group_by = map {$_->[0]{'key'} => TRUE} @paths;
    my @not_grouping_fields = grep {!$fields->{$_} && !$group_by{$_}} keys(%$fields);

    throw Exception::BadArguments gettext("You've forgotten grouping function for query fields: %s",
        join(', ', @not_grouping_fields))
      if @not_grouping_fields;

    $self->{'__GROUP_BY__'}       = \@group_by;
    $self->{'__PATHS_GROUP_BY__'} = \@paths;

    return $self;
}

sub _get_filter {
    my ($self, $filter) = @_;

    my $body = '';

    $self->_filter(\$body, $filter);

    return $self->_get_sub($body);
}

sub _get_sub {
    my ($self, $body) = @_;

    return "sub {\n    no warnings;\n\n    return " . $body . ";\n}";
}

sub _filter {
    my ($self, $body, $filter) = @_;

    my $operation = ' && ';

    $$body .= '(';

    my @part = ();
    if (ref($filter) eq 'HASH') {
        if ([%$filter]->[0] eq 'NOT' && ref($filter->{'NOT'}) eq 'ARRAY') {
            my $sub_body .= 'not (';
            $self->_filter(\$sub_body, $filter->{'NOT'}[0]);
            $sub_body .= ')';

            push(@part, $sub_body);
        } else {
            foreach my $field (keys(%$filter)) {
                my $path = $self->_get_path($field);

                throw gettext('Unknown field "%s"', $path->[0]{'key'})
                  if exists($self->{'__ALL_FIELDS__'}) && !exists($self->{'__ALL_FIELDS__'}{$path->[0]{'key'}});

                my $type_operation = $self->_get_filter_operation($field, '=');

                my $field_code = $self->_get_field_code_by_path('$_[0]', $path);

                if (ref($filter->{$field}) eq 'ARRAY') {
                    push(@part,
                            "(grep {$field_code $type_operation \$_} ("
                          . join(', ', map {$self->_get_value($field, $_)} @{$filter->{$field}})
                          . "))");
                } else {
                    my $value = $self->_get_value($field, $filter->{$field});

                    push(@part, "($field_code $type_operation $value)");
                }
            }
        }
    } elsif (ref($filter) eq 'ARRAY' && @$filter == 2) {
        $operation = ' || ' if uc($filter->[0]) eq 'OR';

        foreach my $sub_filter (@{$filter->[1]}) {
            my $sub_body = '';
            $self->_filter(\$sub_body, $sub_filter);
            push(@part, $sub_body);
        }
    } elsif (ref($filter) eq 'ARRAY' && @$filter == 3) {
        my ($field, $op, $value) = @$filter;

        my $path = $self->_get_path($field);

        throw gettext('Unknown field "%s"', $path->[0]{'key'})
          if exists($self->{'__ALL_FIELDS__'}) && !exists($self->{'__ALL_FIELDS__'}{$path->[0]{'key'}});

        $op    = uc($op);
        $value = $$value;

        my $type_operation = $self->_get_filter_operation($field, $op);

        my $field_code = $self->_get_field_code_by_path('$_[0]', $path);

        if (ref($value) eq 'ARRAY') {
            throw gettext('Operation "%s" is not applied to the array', $op)
              if grep {$op eq $_} ('>', '>=', '<', '<=', 'LIKE', 'NOT LIKE', 'IS', 'IS NOT');

            push(@part,
                    "("
                  . ($op eq '<>' || $op eq '!=' || $op eq 'NOT IN' ? '!' : '')
                  . "grep {$field_code $type_operation \$_} ("
                  . join(', ', map {$self->_get_value($field, $_)} @$value)
                  . "))");
        } else {
            throw gettext('Operation "%s" is only applied to the undef', $op)
              if (grep {$op eq $_} ('IS', 'IS NOT')) && defined($value);

            $value = $self->_get_value($field, $value, $op);

            push(@part,
                ($op eq '<>' || $op eq '!=' || $op =~ /^NOT\s|\sNOT$/i ? '!' : '')
                  . "($field_code $type_operation $value)");
        }
    }

    $$body .= join($operation, @part);

    $$body .= ')';
}

sub _get_order {
    my ($self, @order_by) = @_;

    my @part = ();
    foreach my $order (@order_by) {
        my $path = $self->_get_path($order->[0]);

        throw gettext('Unknown field "%s"', $path->[0]{'key'})
          if exists($self->{'__ALL_FIELDS__'}) && !exists($self->{'__ALL_FIELDS__'}{$path->[0]{'key'}});

        my $type_operation = $self->_get_order_operation($order->[0]);

        my $value = $self->_get_field_code_by_path('$_[%s]', $path);

        if ($order->[1]) {
            push(@part, sprintf("($value %s $value)", 1, $type_operation, 0));
        } else {
            push(@part, sprintf("($value %s $value)", 0, $type_operation, 1));
        }
    }

    my $body = join(' || ', @part);

    return $self->_get_sub($body);
}

sub _get_path {
    my ($self, $field) = @_;

    my @path = ();
    foreach (split(/\./, $field)) {
        if ($_ =~ /^\[([0-9]+)\]\z/) {
            push(@path, {type => 'array', key => $1});
        } else {
            push(@path, {type => 'hash', key => $_});
        }
    }

    return \@path;
}

sub _get_field_code_by_path {
    my ($self, $value, $path) = @_;

    foreach (@$path) {
        if ($_->{'type'} eq 'array') {
            $value .= "->[$_->{key}]";
        } else {
            $value .= "->{$_->{key}}";
        }
    }

    return $value;
}

sub get_field_value_by_path {
    my ($self, $row, $new_row, $last_field, @paths) = @_;
    #Последний параметр передается как массив для копирования,
    #возможно стоит заменить на ссылку на массив и делать копирование перед вызовом

    unless (@paths) {
        return $last_field eq 'new_row' ? $new_row : $row;
    }

    my $path = shift(@paths);
    my $fields = $self->get_fields() // {};

    if ($path->{'type'} eq 'array') {
        if ($fields->{$path->{'key'}}) {
            return $self->get_field_value_by_path($row, $new_row->[$path->{'key'}], 'new_row', @paths);
        } else {
            return $self->get_field_value_by_path($row->[$path->{'key'}], $new_row, 'row', @paths);
        }
    } else {
        if ($fields->{$path->{'key'}}) {
            return $self->get_field_value_by_path($row, $new_row->{$path->{'key'}}, 'new_row', @paths);
        } else {
            return $self->get_field_value_by_path($row->{$path->{'key'}}, $new_row, 'row', @paths);
        }
    }
}

sub _get_filter_operation {
    my ($self, $field, $op) = @_;

    my $type = $self->definition->{$field}{'type'} // 'string';

    return $FILTER_OPERATIONS->{$type}{$op} // throw gettext('Unknow operation "%s"', $op);
}

sub _get_order_operation {
    my ($self, $field) = @_;

    my $type = $self->definition->{$field}{'type'} // 'string';

    return $ORDER_OPERATIONS->{$type};
}

sub _get_value {
    my ($self, $field, $value, $op) = @_;

    return 'undef' unless defined($value);

    #TODO: REGEXP
    if (defined($op) && $op =~ /LIKE/i) {
        return 'm/' . quotemeta($value) . '/' . ($self->{'__INSENSITIVE__'} ? 'i' : '');
    }

    my $type = $self->definition->{$field}{'type'} // 'string';

    if ($type eq 'string') {
        $value =~ s/\\/\\\\/g;
        $value =~ s/'/\\'/g;
        $value = "'$value'";
    } else {
        throw gettext('%s - not number', $value) unless looks_like_number($value);
    }

    return $value;
}

TRUE;

__END__

=encoding utf8

=head1 Name

QBit::QueryData - Query constructor for the data.

=head1 GitHub

https://github.com/QBitFramework/QBit-QueryData

=head1 Install

=over

=item *

cpanm QBit::QueryData

=item *

apt-get install libqbit-querydata-perl (http://perlhub.ru/)

=back

=head1 Methods

=over

=item *

B<new> - created object. Params:

=over

=item *

B<data> - data.

=item *

B<fields> - default fields (optional, defualt all fields)

=item *

B<filter> - default filter (optional, default all data)

=item *

B<definition> - fields definition (optional, default 'string')

=back

B<Example:>

    my $q = QBit::QueryData->new(
        data => [
            {
                id      => 1,
                caption => 'c1',
                data    => {
                    k1 => 1.1,
                    k2 => 'd1_2'
                },
                array => [1.1, 'a1_2'],
            },
            {
                id      => 2,
                caption => 'c2',
                data    => {
                    k1 => 2.1,
                    k2 => 'd2_2'
                },
                array => [2.1, 'a2_2'],
            },
        ],
        fields => [qw(id caption)],
        filter => ['OR', [
            {id => 1},
            ['caption'   => '=' => \'c2'],
            ['data.k1'   => '>', \2],
            ['array.[1]' => 'LIKE' => \'a1']
        ]],
        definition => {
            'id'        => {type => 'number'},
            'caption'   => {type => 'string'},
            'data.k1'   => {type => 'number'},
            'data.k2'   => {type => 'string'},
            'array.[0]' => {type => 'number'},
            'array.[1]' => {type => 'string'},
        },
    );

=item *

B<fields> - set fields for request

B<Example:>

    # set fields
    $q->fields([qw(caption)]);
    $q->fields({
        caption => '',
        key => 'id', # create alias 'key' for field 'id'
    });

    # use default fields
    $q->fields([]);
    $q->fields({});

    # all fields
    $q->fields();

=item *

B<get_fields> - get fields

B<Example:>

    my $fields = $q->get_fields(); # {'caption' => '', 'key' => 'id'}

=item *

B<filter> - set filter for request

Types:

=over

=item *

number: "=" "<>" "!=" ">" ">=" "<" "<=" "IN" "NOT IN" "IS" "IS NOT"

=item *

string: "=" "<>" "!=" ">" ">=" "<" "<=" "IN" "NOT IN" "IS" "IS NOT" "LIKE" "NOT LIKE"

=back

For list: "=" "<>" "!=" "IN" "NOT IN"

B<Example:>

    $q->filter({id => 1, caption => 'c1'}); # or ['AND', [['id' => '=' => \1], ['caption' => '=' => \'c1']]]

    $q->filter(['caption' => 'LIKE' => \'c']);

    $q->filter(['data.k1' => '<' => \2]);

    $q->filter(['array.[1]' => '=' => \'a2_2']);

    $q->filter(); # all data

=item *

B<definition> - set fields definition

B<Example:>

    $q->definition({
        'id'        => {type => 'number'},
        'caption'   => {type => 'string'},
        'data.k1'   => {type => 'number'},
        'data.k2'   => {type => 'string'},
        'array.[0]' => {type => 'number'},
        'array.[1]' => {type => 'string'},
    });

=item *

B<group_by> - grouping by fields

B<Example:>

    $q->group_by(qw(caption data.k1 array.[1]));

=item *

B<order_by> - set order sorting

B<Example:>

    # Ascending
    $q->order_by(qw(id caption data.k1 array.[1])); # or (['id', 0], ['caption', 0], ['data.k1', 0], ['array.[1]', 0])

    # Descending
    $q->order_by(['id', 1]);
    
=item *

B<limit> - set offset and limit

B<Example:>

    $q->limit($offset, $limit);

    $q->limit(); # all data

=item *

B<found_rows> - data count

B<Example:>

    my $rows = $q->found_rows(); # 2

=item *

B<distinct> - set/reset only unique elements

B<Example:>

    #set
    $q->distinct(1); # or $q->distinct();

    #reset
    $q->distinct(0);

=item *

B<insensitive> - set/reset insensitive mode for LIKE 

B<Example:>

    #set
    $q->insensitive(1); # or $q->insensitive();

    #reset
    $q->insensitive(0);

=item *

B<get_all> - get data by settings

B<Example:>

    my $data = $q->get_all();

    $data = $q->fields([qw(id)])->filter(['caption' => 'LIKE' => \'c'])->group_by('id')->order_by(['id', 1])->get_all();

=item *

B<all_langs> - support interface DB::Query

=item *

B<calc_rows> - support interface DB::Query

=item *

B<for_update> - support interface DB::Query

=back

=cut
