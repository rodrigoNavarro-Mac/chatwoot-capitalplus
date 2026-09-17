import { mount } from '@vue/test-utils';
import FunnelStageMeter from '../FunnelStageMeter.vue';

describe('FunnelStageMeter.vue', () => {
  const baseProps = {
    icon: 'i-lucide-users',
    label: 'Leads',
    count: 100,
    actualPercent: 100,
  };

  it('renders the count and percent without a lost segment when lostCount is not passed', () => {
    const wrapper = mount(FunnelStageMeter, { props: baseProps });

    expect(wrapper.text()).toContain('100');
    expect(wrapper.find('.bg-n-ruby-9').exists()).toBe(false);
  });

  it('shows a red segment and badge proportional to lostCount, without treating it as additive', () => {
    const wrapper = mount(FunnelStageMeter, {
      props: {
        ...baseProps,
        count: 20,
        lostCount: 5,
        lostTooltip: 'lost here',
      },
    });

    // El badge muestra el número tal cual, sin "+" (no es una cantidad aparte que se sume a count).
    expect(wrapper.text()).toContain('(5)');
    const lostBar = wrapper.find('.bg-n-ruby-9');
    expect(lostBar.exists()).toBe(true);
    // 5 de 20 = 25% del ancho visible (actualPercent=100 sin recortar).
    expect(lostBar.attributes('style')).toContain('width: 25%');
  });

  it('does not change the existing activity/external segments when lostCount is absent (backward-compatible with Sales Funnel)', () => {
    const wrapper = mount(FunnelStageMeter, {
      props: {
        ...baseProps,
        count: 10,
        activityCount: 4,
        activityTooltip: 'activity',
      },
    });

    const activityBar = wrapper.find('.bg-n-amber-10');
    expect(activityBar.attributes('style')).toContain('width: 40%');
  });
});
