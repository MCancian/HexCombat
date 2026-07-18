import math

def mean(samples):
    if not samples:
        return 0.0
    return sum(samples) / len(samples)

def stdev(samples, m):
    if len(samples) < 2:
        return 0.0
    variance = sum((x - m) ** 2 for x in samples) / (len(samples) - 1)
    return math.sqrt(variance)

def crossing_loss_pct(cell_data):
    losses = []
    for s in cell_data['samples']:
        wave = float(s.get('wave_bns', 0))
        if wave == 0:
            losses.append(0.0)
        else:
            losses.append(100.0 * float(s.get('bns_lost_at_sea', 0)) / wave)
    m = mean(losses)
    sd = stdev(losses, m)
    return f"{m:.1f}±{sd:.1f}"

def maneuver_attrition_pct(cell_data):
    pools = []
    killeds = []
    warmups = []
    taiwans = []
    
    for s in cell_data['samples']:
        pool = float(s['pool'])
        killed = float(s['killed'])
        pools.append(pool)
        killeds.append(killed)
        warmups.append(float(s['warmup_killed']))
        taiwans.append(float(s['taiwan']))
        
    m_killed = mean(killeds)
    m_pool = mean(pools)
    m_pct = 100.0 * m_killed / m_pool if m_pool > 0 else 0.0
    sd_killed = stdev(killeds, m_killed)
    m_warmup = mean(warmups)
    m_taiwan = mean(taiwans)
    
    return {
        "pool": f"{m_pool:.0f}",
        "killed(mean+/-sd)": f"{m_killed:.1f}+/-{sd_killed:.1f}",
        "%pool": f"{m_pct:.0f}%",
        "warmup_killed(mean)": f"{m_warmup:.1f}",
        "taiwan_census(mean)": f"{m_taiwan:.1f}"
    }

REGISTRY = {
    "crossing_loss_pct": crossing_loss_pct,
    "maneuver_attrition_pct": maneuver_attrition_pct,
}
