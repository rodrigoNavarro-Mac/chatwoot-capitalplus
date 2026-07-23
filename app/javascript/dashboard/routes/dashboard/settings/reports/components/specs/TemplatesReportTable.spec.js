import { mount } from '@vue/test-utils';
import TemplatesReportTable from '../TemplatesReportTable.vue';

const rows = [
  {
    template_name: 'bienvenida',
    sent: 100,
    delivered: 90,
    read: 80,
    failed: 5,
    responded: 40,
    response_rate: 40.0,
  },
  {
    template_name: 'seguimiento_1',
    sent: 60,
    delivered: 55,
    read: 50,
    failed: 2,
    responded: 10,
    response_rate: 16.67,
  },
];

describe('TemplatesReportTable.vue', () => {
  it('renders the empty state when there are no rows', () => {
    const wrapper = mount(TemplatesReportTable, { props: { rows: [] } });

    expect(wrapper.find('table').exists()).toBe(false);
  });

  it('renders one row per template with its metrics', () => {
    const wrapper = mount(TemplatesReportTable, { props: { rows } });

    const tableRows = wrapper.findAll('tbody tr');
    expect(tableRows).toHaveLength(2);
    expect(wrapper.text()).toContain('bienvenida');
    expect(wrapper.text()).toContain('seguimiento_1');
    expect(wrapper.text()).toContain('40%');
    expect(wrapper.text()).toContain('16.67%');
  });
});
