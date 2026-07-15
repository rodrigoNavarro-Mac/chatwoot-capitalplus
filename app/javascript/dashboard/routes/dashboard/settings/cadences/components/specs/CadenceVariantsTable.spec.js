import { mount } from '@vue/test-utils';
import CadenceVariantsTable from '../CadenceVariantsTable.vue';

const variants = [
  {
    id: 1,
    name: 'Inversión — A',
    segment_value: 'Inversión',
    is_default: false,
    leads_in_cadence: 40,
    responded_count: 20,
    response_rate: 50.0,
    recovered_count: 5,
    cold_count: 15,
  },
  {
    id: 2,
    name: 'Inversión — B',
    segment_value: 'Inversión',
    is_default: false,
    leads_in_cadence: 38,
    responded_count: 10,
    response_rate: 26.32,
    recovered_count: 2,
    cold_count: 26,
  },
];

describe('CadenceVariantsTable.vue', () => {
  it('renders nothing when there are no variants', () => {
    const wrapper = mount(CadenceVariantsTable, { props: { variants: [] } });

    expect(wrapper.find('table').exists()).toBe(false);
  });

  it('renders one row per variant with its metrics', () => {
    const wrapper = mount(CadenceVariantsTable, { props: { variants } });

    const rows = wrapper.findAll('tbody tr');
    expect(rows).toHaveLength(2);
    expect(wrapper.text()).toContain('Inversión — A');
    expect(wrapper.text()).toContain('Inversión — B');
    expect(wrapper.text()).toContain('50%');
    expect(wrapper.text()).toContain('26.32%');
  });

  it('shows the default badge only for the default cadence', () => {
    const wrapper = mount(CadenceVariantsTable, {
      props: {
        variants: [{ ...variants[0], is_default: true }, variants[1]],
      },
    });

    const rows = wrapper.findAll('tbody tr');
    expect(rows[0].text()).toContain('Default');
    expect(rows[1].text()).not.toContain('Default');
  });
});
