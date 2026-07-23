import { mount } from '@vue/test-utils';
import TemplatesReportTimeseriesTable from '../TemplatesReportTimeseriesTable.vue';

const rows = [
  {
    period: '2026-07-20',
    template_name: 'bienvenida',
    sent: 20,
    delivered: 18,
    read: 15,
    failed: 1,
    responded: 8,
    response_rate: 40.0,
  },
  {
    period: '2026-07-21',
    template_name: 'bienvenida',
    sent: 25,
    delivered: 24,
    read: 20,
    failed: 0,
    responded: 12,
    response_rate: 48.0,
  },
];

describe('TemplatesReportTimeseriesTable.vue', () => {
  it('renders the empty state when there are no rows', () => {
    const wrapper = mount(TemplatesReportTimeseriesTable, {
      props: { rows: [] },
    });

    expect(wrapper.find('table').exists()).toBe(false);
  });

  it('renders one row per period/template combination', () => {
    const wrapper = mount(TemplatesReportTimeseriesTable, {
      props: { rows },
    });

    const tableRows = wrapper.findAll('tbody tr');
    expect(tableRows).toHaveLength(2);
    expect(wrapper.text()).toContain('2026-07-20');
    expect(wrapper.text()).toContain('2026-07-21');
    expect(wrapper.text()).toContain('40%');
    expect(wrapper.text()).toContain('48%');
  });
});
