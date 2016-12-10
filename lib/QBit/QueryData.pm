package QBit::QueryData;

use qbit;

use base qw(QBit::Class);

__PACKAGE__->mk_accessors(qw(data definition));

my $FILTER_OPERATIONS = {
    number => {
        '='        => '==',
        '!='       => '!=',
        '<>'       => '!=',
        '>'        => '>',
        '>='       => '>=',
        '<'        => '<',
        '<='       => '<=',
        'IN'       => '==',
        'NOT IN'   => '==',
        'IS'       => '==',
        'IS NOT'   => '==',
        'LIKE'     => '=~',
        'NOT LIKE' => '=~',
    },
    string => {
        '='        => 'eq',
        '!='       => 'ne',
        '<>'       => 'ne',
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

    $self->data([]) unless defined($self->data);

    $self->definition({}) unless defined($self->definition);

    $self->fields($self->get_fields());

    $self->filter($self->{'filter'});
}

sub fields {
    my ($self, $fields) = @_;

    if (defined($fields)) {
        if (@$fields == 0) {
            #default
            delete($self->{'__FIELDS__'});
        } else {
            #set fields
            $self->{'__FIELDS__'} = $fields;
        }
    } else {
        #all fields
        delete($self->{'__FIELDS__'});
        delete($self->{'fields'});
    }

    return $self;
}

sub get_fields {
    my ($self) = @_;

    return $self->{'__FIELDS__'} // $self->{'fields'} // [sort keys(%{$self->data->[0] // {}})];
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

    $self->{'__OFFSET__'} = $offset;

    $self->{'__LIMIT__'} = $limit;

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

    my @data = defined($self->{'__FILTER__'}) ? grep {$self->{'__FILTER__'}->($_)} @{$self->data} : @{$self->data};

    if (defined($self->{'__ORDER_BY__'})) {
        @data = sort {$self->{'__ORDER_BY__'}->($a, $b)} @data;
    }

    if (defined($self->{'__LIMIT__'})) {
        $self->{'__OFFSET__'} //= 0;

        return [] if $self->{'__OFFSET__'} > @data;

        my $high = $self->{'__LIMIT__'} + $self->{'__OFFSET__'};

        $high = $high > @data ? $#data : $high - 1;

        @data = @data[$self->{'__OFFSET__'} .. $high];
    }

    my @result = ();

    my @fields = @{$self->get_fields()};
    if ($self->{'__DISTINCT__'}) {
        my %uniq = ();

        foreach my $row (@data) {
            my $str = '';

            my $new_row = {};
            foreach (@fields) {
                $str .= $row->{$_} // 'UNDEF';

                $new_row->{$_} = $row->{$_};
            }

            unless ($uniq{$str}) {
                push(@result, $new_row);

                $uniq{$str} = TRUE;
            }
        }
    } else {
        foreach my $row (@data) {
            push(@result, {map {$_ => $row->{$_}} @fields});
        }
    }

    return \@result;
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
        foreach my $field (keys(%$filter)) {
            my $type_operation = $self->_get_filter_operation($field, '=');

            if (ref($filter->{$field}) eq 'ARRAY') {
                push(@part,
                        "(grep {\$_[0]->{$field} $type_operation \$_} ("
                      . join(', ', map {$self->_get_value($field, $_)} @{$filter->{$field}})
                      . "))");
            } else {
                my $value = $self->_get_value($field, $filter->{$field});

                push(@part, "(\$_[0]->{$field} $type_operation $value)");
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

        my $not = ($op =~ /^NOT\s|\sNOT$/i);

        my $type_operation = $self->_get_filter_operation($field, $op);
        $value = $self->_get_value($field, $value, $op);

        if (ref($value) eq 'ARRAY') {
            push(@part,
                    "("
                  . ($not ? '!' : '')
                  . "grep {\$_[0]->{$field} $type_operation \$_} ("
                  . join(', ', map {$self->_get_value($field, $_)} @$value)
                  . "))");
        } else {
            push(@part, ($not ? '!' : '') . "(\$_[0]->{$field} $type_operation $value)");
        }
    }

    $$body .= join($operation, @part);

    $$body .= ')';
}

sub _get_order {
    my ($self, @order_by) = @_;

    my @part = ();
    foreach my $order (@order_by) {
        my $type_operation = $self->_get_order_operation($order->[0]);

        unless ($order->[1]) {
            push(@part, "(\$_[0]->{$order->[0]} $type_operation \$_[1]->{$order->[0]})");
        } else {
            push(@part, "(\$_[1]->{$order->[0]} $type_operation \$_[0]->{$order->[0]})");
        }
    }

    my $body = join(' || ', @part);

    return $self->_get_sub($body);
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
        $value =~ s/'/\\'/g;
        $value = "'$value'";
    }

    return $value;
}

TRUE;
