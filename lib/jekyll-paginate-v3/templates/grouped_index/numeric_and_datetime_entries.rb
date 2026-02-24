# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates
class GroupedIndex
	# Numeric and datetime grouped-index entry builders.
	# Structure: span boundaries are calculated from canonical config, then
	# candidate items are allocated to spans and emitted as template entries.

	private
	def build_numeric_entries(candidates, config)
		candidate_items = candidates.map do |candidate|
			{
				'item' => candidate['item'],
				'value' => candidate['numeric']
			}
		end.select { |entry| !entry['value'].nil? }

		spans = build_numeric_spans(candidate_items, config)
		build_numeric_entries_from_spans(spans, candidate_items, config)
	end

	# Creates numeric span boundaries according to config, growth, and
	# safety limits.
	def build_numeric_spans(candidate_items, config)
		start_value = config['start'].to_f
		total_groups = config['total']
		step_pattern = config['step_pattern']
		grow_factor = config['grow']
		min_step = config['min_step']
		max_step = config['max_step']

		max_item_value = candidate_items.map { |entry| entry['value'].to_f }.max

		group_count = if total_groups.nil?
										infer_automatic_numeric_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
									else
										total_groups
									end

		group_count = 1 if group_count <= 0 && config['empty']
		return [] if group_count <= 0

		spans = []
		current_start = start_value
		current_step = nil

		group_count.times do |index|
			current_step = numeric_step_for_group(index, current_step, step_pattern, grow_factor, min_step, max_step)
			calculated_end = current_start + current_step
			# With explicit `total`, the final group remains open-ended.
			open_ended = !total_groups.nil? && index == group_count - 1

			spans << {
				'index' => index + 1,
				'start' => current_start,
				'end' => open_ended ? nil : calculated_end,
				'token_upper_bound' => calculated_end
			}

			current_start = calculated_end
		end

		spans
	end

	# Calculates how many numeric spans are needed when `total` is not
	# explicitly configured.
	def infer_automatic_numeric_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
		return 0 if max_item_value.nil?
		return 0 if max_item_value < start_value

		groups = 0
		current_start = start_value.to_f
		current_step = nil

		while current_start < max_item_value
			groups += 1
			if groups > MAXIMUM_AUTOMATIC_GROUPS
				raise ArgumentError, "Grouped indexing implies more than #{MAXIMUM_AUTOMATIC_GROUPS} groups; set `group.total` to opt in explicitly."
			end

			current_step = numeric_step_for_group(groups - 1, current_step, step_pattern, grow_factor, min_step, max_step)
			current_start += current_step
		end

		[groups, 1].max
	end

	# Resolves step size for one numeric group index.
	def numeric_step_for_group(index, previous_step, step_pattern, grow_factor, min_step, max_step)
		base_step = step_pattern[[index, step_pattern.length - 1].min].to_f

		step = if index.zero?
							base_step
						elsif step_pattern.length > 1
							# Pattern arrays pin each group to configured step values.
							base_step
						else
							# Scalar patterns grow iteratively by `grow_factor`.
							previous_step.to_f * grow_factor
						end

		step = clamp_numeric_step(step, min_step: min_step, max_step: max_step)
		raise ArgumentError, 'Numeric grouped indexing produced a non-positive step size.' if step <= 0.0

		step
	end

	# Applies configured and hard safety bounds to one numeric step.
	def clamp_numeric_step(step, min_step:, max_step:)
		lower_bound = min_step.nil? ? MINIMUM_STEP : [min_step.to_f, MINIMUM_STEP].max
		upper_bound = max_step.nil? ? MAXIMUM_STEP : [max_step.to_f, MAXIMUM_STEP].min

		[[step, lower_bound].max, upper_bound].min
	end

	# Builds concrete numeric grouped entries and attaches matching items.
	def build_numeric_entries_from_spans(spans, candidate_items, config)
		grouped_items = spans.each_with_object({}) { |span, memo| memo[span['index']] = [] }

		candidate_items.each do |entry|
			value = entry['value'].to_f
			span = spans.find do |candidate_span|
				# First matching span wins; spans are generated in order.
				range_value_within_span?(value, candidate_span['start'], candidate_span['end'], first_group: candidate_span['index'] == 1)
			end
			next if span.nil?

			grouped_items[span['index']] << entry['item']
		end

		entries = []
		spans.each do |span|
			items = grouped_items.fetch(span['index'])
			next if items.empty? && !config['empty']

			placeholder_value = format_numeric_token(span['token_upper_bound'])

			entry_filter = build_range_filter(
				min_value: span['start'],
				max_value: span['end'],
				min_inclusive: span['index'] == 1
			)

			entries << {
				'filters' => {
					@key => entry_filter
				},
				'values' => {
					@key => placeholder_value
				},
				'token_values' => {
					@key => {
						'title' => placeholder_value,
						'permalink' => placeholder_value
					}
				},
				'group' => {
					'mode' => 'numeric',
					'start' => format_numeric_token(span['start']),
					'end' => span['end'].nil? ? nil : format_numeric_token(span['end']),
					'order' => span['index'],
					'range' => true,
					'other' => false
				},
				'items' => items.uniq
			}
		end

		entries
	end

	# Builds grouped entries for datetime mode.
	def build_datetime_entries(candidates, config)
		candidate_items = candidates.map do |candidate|
			{
				'item' => candidate['item'],
				'value' => candidate['datetime']
			}
		end.select { |entry| !entry['value'].nil? }

		spans = build_datetime_spans(candidate_items, config)
		build_datetime_entries_from_spans(spans, candidate_items, config)
	end

	# Creates datetime span boundaries according to calendar-aware step
	# increments.
	def build_datetime_spans(candidate_items, config)
		start_value = config['start']
		total_groups = config['total']
		step_pattern = config['step_pattern']
		grow_factor = config['grow']
		min_step = config['min_step']
		max_step = config['max_step']

		max_item_value = candidate_items.map { |entry| entry['value'] }.max

		group_count = if total_groups.nil?
										infer_automatic_datetime_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
									else
										total_groups
									end

		group_count = 1 if group_count <= 0 && config['empty']
		return [] if group_count <= 0

		spans = []
		current_start = start_value
		current_step = nil

		group_count.times do |index|
			current_step = datetime_step_for_group(index, current_step, step_pattern, grow_factor, min_step, max_step)
			calculated_end = add_datetime_duration(current_start, current_step)
			# With explicit `total`, the final datetime group is open-ended.
			open_ended = !total_groups.nil? && index == group_count - 1

			spans << {
				'index' => index + 1,
				'start' => current_start,
				'end' => open_ended ? nil : calculated_end,
				'token_upper_bound' => calculated_end
			}

			current_start = calculated_end
		end

		spans
	end

	# Calculates how many datetime spans are needed when `total` is not
	# explicitly configured.
	def infer_automatic_datetime_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
		return 0 if max_item_value.nil?
		return 0 if max_item_value < start_value

		groups = 0
		current_start = start_value
		current_step = nil

		while current_start < max_item_value
			groups += 1
			if groups > MAXIMUM_AUTOMATIC_GROUPS
				raise ArgumentError, "Grouped indexing implies more than #{MAXIMUM_AUTOMATIC_GROUPS} groups; set `group.total` to opt in explicitly."
			end

			current_step = datetime_step_for_group(groups - 1, current_step, step_pattern, grow_factor, min_step, max_step)
			current_start = add_datetime_duration(current_start, current_step)
		end

		[groups, 1].max
	end

	# Resolves step value for one datetime group index, applying growth
	# and configured/hard safety bounds.
	def datetime_step_for_group(index, previous_step, step_pattern, grow_factor, min_step, max_step)
		base_step = Utils.deep_copy(step_pattern[[index, step_pattern.length - 1].min])

		resolved_step = if index.zero?
											base_step
										elsif step_pattern.length > 1
											# Pattern arrays use explicit step sequence values.
											base_step
										else
											# Scalar patterns apply multiplicative growth per group.
											grown = Utils.deep_copy(previous_step)
											grown['amount'] = grown['amount'].to_f * grow_factor
											grown
										end

		resolved_step = clamp_datetime_step(resolved_step, min_step: min_step, max_step: max_step)
		if resolved_step['amount'].to_f <= 0.0
			raise ArgumentError, 'Datetime grouped indexing produced a non-positive step size.'
		end

		resolved_step
	end

	# Applies configured and hard safety bounds to one datetime step.
	def clamp_datetime_step(step, min_step:, max_step:)
		scalar = datetime_duration_to_scalar(step)

		min_scalar = if min_step.nil?
										MINIMUM_STEP
									else
										[datetime_duration_to_scalar(min_step), MINIMUM_STEP].max
									end
		max_scalar = if max_step.nil?
										MAXIMUM_STEP
									else
										[datetime_duration_to_scalar(max_step), MAXIMUM_STEP].min
									end

		clamped_scalar = [[scalar, min_scalar].max, max_scalar].min
		datetime_scalar_to_duration(clamped_scalar, template: step)
	end

	# Converts one datetime duration to a comparable scalar:
	# - calendar units as months
	# - fixed units as days
	def datetime_duration_to_scalar(duration)
		unit = duration['unit']
		amount = duration['amount'].to_f

		case unit
		when 'year'
			amount * 12.0
		when 'month'
			amount
		when 'day'
			amount
		when 'hour'
			amount / 24.0
		when 'minute'
			amount / 1_440.0
		when 'second'
			amount / 86_400.0
		else
			amount
		end
	end

	# Converts a clamped scalar back into the original duration unit.
	def datetime_scalar_to_duration(scalar_value, template:)
		unit = template['unit']
		case unit
		when 'year'
			amount = (scalar_value / 12.0).round
			amount = 1 if amount < 1
		when 'month'
			amount = scalar_value.round
			amount = 1 if amount < 1
		when 'day'
			amount = scalar_value.to_f
		when 'hour'
			amount = scalar_value.to_f * 24.0
		when 'minute'
			amount = scalar_value.to_f * 1_440.0
		when 'second'
			amount = scalar_value.to_f * 86_400.0
		else
			amount = scalar_value.to_f
		end

		{
			'unit' => unit,
			'amount' => amount
		}
	end

	# Adds one parsed duration to a DateTime using calendar-aware month
	# and year operations.
	def add_datetime_duration(datetime_value, duration)
		unit = duration['unit']
		amount = duration['amount']

		case unit
		when 'year'
			datetime_value >> (amount.to_i * 12)
		when 'month'
			datetime_value >> amount.to_i
		when 'day'
			datetime_value + Rational((amount.to_f * 86_400).round, 86_400)
		when 'hour'
			datetime_value + Rational((amount.to_f * 3_600).round, 86_400)
		when 'minute'
			datetime_value + Rational((amount.to_f * 60).round, 86_400)
		when 'second'
			datetime_value + Rational(amount.to_f.round, 86_400)
		else
			datetime_value + Rational((amount.to_f * 86_400).round, 86_400)
		end
	end

	# Builds concrete datetime grouped entries and attaches matching items.
	def build_datetime_entries_from_spans(spans, candidate_items, config)
		grouped_items = spans.each_with_object({}) { |span, memo| memo[span['index']] = [] }

		candidate_items.each do |entry|
			value = entry['value']
			span = spans.find do |candidate_span|
				# First matching span wins; spans are generated in order.
				range_value_within_span?(value, candidate_span['start'], candidate_span['end'], first_group: candidate_span['index'] == 1)
			end
			next if span.nil?

			grouped_items[span['index']] << entry['item']
		end

		entries = []
		spans.each do |span|
			items = grouped_items.fetch(span['index'])
			next if items.empty? && !config['empty']

			title_token = format_datetime_title_token(span['token_upper_bound'])
			permalink_token = format_datetime_permalink_token(span['token_upper_bound'], include_time: config['time_precision'])

			entry_filter = build_range_filter(
				min_value: span['start'],
				max_value: span['end'],
				min_inclusive: span['index'] == 1
			)

			entries << {
				'filters' => {
					@key => entry_filter
				},
				'values' => {
					@key => title_token
				},
				'token_values' => {
					@key => {
						'title' => title_token,
						'permalink' => permalink_token
					}
				},
				'group' => {
					'mode' => 'datetime',
					'start' => format_datetime_title_token(span['start']),
					'end' => span['end'].nil? ? nil : format_datetime_title_token(span['end']),
					'order' => span['index'],
					'range' => true,
					'other' => false
				},
				'items' => items.uniq
			}
		end

		entries
	end

end
end
end
end
end
