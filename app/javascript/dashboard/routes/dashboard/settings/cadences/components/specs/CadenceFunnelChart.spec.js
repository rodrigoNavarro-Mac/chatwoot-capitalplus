import { mount } from '@vue/test-utils';
import CadenceFunnelChart from '../CadenceFunnelChart.vue';

const steps = [
  { step: 1, template_key: 'wa_paso_1', sent: 100, drop_off_rate: 0.0 },
  { step: 2, template_key: 'wa_paso_2', sent: 60, drop_off_rate: 40.0 },
  { step: 3, template_key: 'wa_paso_3', sent: 30, drop_off_rate: 50.0 },
];

describe('CadenceFunnelChart.vue', () => {
  it('renders nothing when there are no steps', () => {
    const wrapper = mount(CadenceFunnelChart, { props: { steps: [] } });

    expect(wrapper.find('div').exists()).toBe(false);
  });

  it('renders one row per step with sent count and drop-off', () => {
    const wrapper = mount(CadenceFunnelChart, { props: { steps } });

    expect(wrapper.text()).toContain('100 sent');
    expect(wrapper.text()).toContain('60 sent');
    expect(wrapper.text()).toContain('-40% vs. previous step');
    expect(wrapper.text()).toContain('-50% vs. previous step');
  });

  it('does not show a drop-off badge for the first step', () => {
    const wrapper = mount(CadenceFunnelChart, { props: { steps } });

    const rows = wrapper.findAll('.flex.items-center.gap-3');
    expect(rows[0].text()).not.toContain('vs. previous step');
  });
});
